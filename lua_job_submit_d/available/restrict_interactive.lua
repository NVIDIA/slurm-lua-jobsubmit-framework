-- SPDX-FileCopyrightText: Copyright (c) 2024-2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
-- SPDX-License-Identifier: Apache-2.0
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- ========================================================================
--
-- luacheck: std lua51
-- luacheck: allow defined top
-- luacheck: globals slurm _
------------------------------------------------------------------------------
--
-- This plugin forbids running or restricts max time for batch jobs in interactive partitions.
-- List of such partitions is specified in file `/etc/slurm/interactive_partitions`.
-- The list is cached, in case you need to reload it, touch the file `/etc/slurm/interactive_partitions.update`.
--
-- Filenames are tunable - see restrict_interactive definition
-- "update" file path is made of interactive_partitions file plus ".update"
--
-- File format:
-- partition = -  #<- forbid any batch job
-- partition = 10 #<- max time = 10 minutes
-- DEFAULT =20    #<- max time (or - for forbid) for DEFAULT partition
--                # THIS ENTRY WORKS IN CASE WHEN `-p` IS NOT USED. E.g.: `sbatch --wrap hostname`
-- __debug__=1    #<- increase debug logging level
------------------------------------------------------------------------------

local restrict_interactive = {
  debug = 0,
  interactive_partitions_file = "/etc/slurm/interactive_partitions"
}
local the_table = nil

function restrict_interactive.log(str)
  if restrict_interactive.debug ~= 0 then
    slurm.log_info(str)
  end
end
--
-- Check if config file even exists
--
function restrict_interactive.file_exists(file_path)
  local f = io.open(file_path, "rb")
  if f then
    f:close()
  end
  return f ~= nil
end

--
-- file contains just a list of something; this function reads the file
-- and returns the table with keys as lines and values as 'true'
--
function restrict_interactive.file_to_truth_table(file_path)
  local t = {}
  local empty = true
  local name
  local limit

  if not restrict_interactive.file_exists(file_path) then
    return {}
  end
  slurm.log_info("restrict_interactive lua plugin: loading config:")

  for line in io.lines(file_path) do
    _, _, name, limit = string.find(line, "^%s*(%S+)%s*=%s*(%S+)")
    if name and name ~= "" then
      if name == "__debug__" then
        restrict_interactive.debug = tonumber(limit)
        if restrict_interactive.debug ~= 0 then
          slurm.log_info("restrict_interactive lua plugin: DEBUG activated")
        end
      else
        empty = false
        if limit == '-' then
          t[name] = -1
        else
          t[name] = tonumber(limit) or -1
        end
        slurm.log_info("restrict_interactive lua plugin: "..name.." = "..t[name])
      end
    end
  end
  slurm.log_info("restrict_interactive lua plugin: loaded config")
  if empty then
    return {}
  else
    return t
  end
end

--
-- Load the file with restrictions.
-- File is cached, to reload it touch /etc/slurm/interactive_partitions.update file or restart slurmctld
-- Returns: the loaded table.
--
function restrict_interactive.get_interactive_partitions_table()
  if restrict_interactive.file_exists(restrict_interactive.interactive_partitions_file .. ".update") then
    the_table = restrict_interactive.file_to_truth_table(restrict_interactive.interactive_partitions_file)
    os.remove(restrict_interactive.interactive_partitions_file .. ".update")
  end
  if the_table == nil then
    the_table = restrict_interactive.file_to_truth_table(restrict_interactive.interactive_partitions_file)
  end
  return the_table
end

--
-- Check is the partition is mentioned in the config file
-- Args:
--   job_desc: job description in SLURM format
-- Returns:
--   partition names ARRAY, if they are affected, false if not.
--
function restrict_interactive.is_partition_affected(job_desc)
  local partitions = restrict_interactive.get_interactive_partitions_table()
  local partition = job_desc.partition or 'DEFAULT'
  local list = {}
  local affected = false
  for part in string.gmatch(partition, '([^,]+)') do
    restrict_interactive.log("restrict_interactive lua plugin: Checking partition ".. part)
    if partitions[part] == nil then
      slurm.log_info("restrict_interactive lua plugin: partition "..(part).." is NOT affected")
      -- return false
    else
      slurm.log_info("restrict_interactive lua plugin: partition "..(part).." IS affected")
      table.insert(list, part)
      affected = true
    end
  end
  if affected then
    return list
  end
  return false
end

--
-- Get the limit for this partition
-- Args:
--   partition: partition name
-- Returns:
--   The time limit value.
--
function restrict_interactive.partition_limit(partition)
  local partitions = restrict_interactive.get_interactive_partitions_table()
  return partitions[(partition or 'DEFAULT')] or -1
end

--
-- Slurm job_submit plugin entrypoints
-- Called when a job is submitted
-- Args:
--   job_desc - table containing details of the submitted job. We can both read
--              and modify these values before the job goes into the queue
--
--   part_list - List of tables corresponding to partitions available to the
--               job (untested)
--   submit_uid - Unix user ID of the user submitting the job (untested)
function restrict_interactive.slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
  local partlist = restrict_interactive.is_partition_affected(job_desc)
  if not partlist then
    -- ignore this partition(s)!
    return slurm.SUCCESS
  end
  if job_desc.environment ~= nil then -- BATCH TASK!
    for _,part in pairs(partlist) do
      local limit = restrict_interactive.partition_limit(part)
      if limit <= 0 then
        slurm.log_user("Use of partition".. part .." for batch jobs is prohibited. Use srun or salloc only.\n")
        restrict_interactive.log("restrict_interactive lua plugin: partition ".. part .." is prohibited. Deny.")
        return slurm.ESLURM_ACCESS_DENIED
      end
      if job_desc.time_limit > limit then
        slurm.log_user("Batch jobs are restricted by " .. limit .. " minutes. Please, change timelimit.\n")
        restrict_interactive.log("restrict_interactive lua plugin: partition ".. part ..", limit ".. limit ..
          ". Job asked for "..job_desc.time_limit ..". Deny.")
        return slurm.ESLURM_ACCESS_DENIED
      end
    end
  end

  local part = job_desc.partition or 'DEFAULT'
  restrict_interactive.log("restrict_interactive lua plugin: partition(s) ".. part ..". INTERACTIVE job asked for "
    .. job_desc.time_limit ..". ALLOW.")
  return slurm.SUCCESS
end

-- Called when a job is modified, as in with scontrol
-- Args:
--   job_desc - table containing details of the submitted job. we can both read
--              and modify these values before the job goes into the queue
--
--   job_rec - table containing details of the changes. we can both read
--              and modify these values before the job goes into the queue
--
--   part_list - List of tables corresponding to partitions available to the
--               job (untested)
--   submit_uid - Unix user ID of the user submitting the job (untested)
function restrict_interactive.slurm_job_modify(job_desc, job_rec, part_list, modify_uid) -- luacheck: ignore
  local partlist = restrict_interactive.is_partition_affected(job_desc)
  if not partlist then
    -- ignore this partition(s)!
    return slurm.SUCCESS
  end
  if job_desc.environment ~= nil then -- BATCH TASK!
    for _,part in pairs(partlist) do
      local limit = restrict_interactive.partition_limit(part)
      slurm.log_info("Limit="..limit)
      if limit <= 0 then
        slurm.log_user("Use of partition" .. part .." for batch jobs is prohibited. Use srun or salloc only.\n")
        return slurm.ESLURM_ACCESS_DENIED
      end
      if job_rec.time_limit > limit then
        slurm.log_user("Batch jobs are restricted by " .. limit .. " minutes. Please, change timelimit.\n")
        return slurm.ESLURM_ACCESS_DENIED
      end
    end
  else
    slurm.log_info("interactive job. Allow.")
  end
  if restrict_interactive.debug ~= 0 then
    local part = job_desc.partition or 'DEFAULT'
    slurm.log_info("restrict_interactive lua plugin: partition ".. part ..". Job asked for "..
      job_desc.time_limit ..". ALLOW.")
  end
  return slurm.SUCCESS
end
------------------------------------------------------------------------------

-- slurm.log_info("restrict_interactive lua plugin loaded")
return restrict_interactive
