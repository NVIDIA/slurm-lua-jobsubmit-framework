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
-- Add information to admin_comments field.
-- In this example we add info about dependencies, network and switches
-- Feel free to modify and put your info
------------------------------------------------------------------------------
--

local enrich_comments = {}

--
-- SIMPLE hash->json translator,
-- supports ONLY strings and numbers as values
--
function enrich_comments.to_json(hash)
  local str = "{"
  local not_first = false
  for k,v in pairs(hash) do
    -- slurm.log_user("ADD: "..k.." = "..v)
    if not_first then
      str = str..", "
    else
      not_first = true
    end
    str = str.."\""..k.."\": ".."\""..tostring(v).."\""
  end
  return str.."}"
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
function enrich_comments.slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
  local data = {}
  local enrich = false
  if job_desc['dependency'] ~= nil then
    data['dependency'] = job_desc['dependency']
    enrich = true
  end
  if job_desc['network'] ~= nil then
    data['network'] = job_desc['network']
    enrich = true
  end

  local sw = job_desc['req_switch']
  if sw ~= nil and sw ~= slurm.NO_VAL and sw ~= slurm.NO_VAL16 and sw ~= slurm.NO_VAL64 then
    data['switches'] = sw
    enrich = true
  end
  if enrich then
    local comment = (job_desc['admin_comment'] or '')
    if comment == '' then
      job_desc['admin_comment'] = enrich_comments.to_json(data)
    else
      job_desc['admin_comment'] = comment.."; "..enrich_comments.to_json(data)
    end
  end
  return slurm.SUCCESS
end

-- Called when a job is modified, as in with scontrol
-- Args: TBD (not used yet)
function enrich_comments.slurm_job_modify(job_desc, job_rec, part_list, modify_uid) -- luacheck: ignore
  return slurm.SUCCESS
end
------------------------------------------------------------------------------

-- slurm.log_info("enrich_comments lua plugin loaded")
return enrich_comments
