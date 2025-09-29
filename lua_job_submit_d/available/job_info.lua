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
------------------------------------------------------------------------------
--
-- Debug module - prints the job attributes, available via slurm
-- Note! In new slurm versions the set of attributes can change,
-- check it in the slurm source code (yes, that's life)
--

local job_info = {}

function job_info._job_info(job_desc, part_list, submit_uid) -- luacheck: ignore
  local attr_names = {
    "account","accounts","acctg_freq","admin_comment","alloc_node","allow_accounts",
    "allow_alloc_nodes","allow_groups","allow_qos","alternate","argc","argv",
    "array_inx","assoc_list","batch_features","begin_time","billing_weights_str",
    "bitflags","boards_per_node","burst_buffer","clusters","comment","container",
    "contiguous","cores_per_socket","cpu_freq_gov","cpu_freq_max","cpu_freq_min",
    "cpus_per_task","cpus_per_tres","cron_job","def_mem_per_cpu","def_mem_per_node",
    "default_account","default_qos","default_time","delay_boot","deny_accounts",
    "deny_qos","dependency","duration","end_time","environment","exc_nodes","extra",
    "features","flag_default","flags_set_node","flags","full_nodes","gres","group_id",
    "het_job_offset","immediate","licenses","mail_type","mail_user","max_cpus_per_node",
    "max_cpus_per_socket","max_cpus","max_mem_per_cpu","max_mem_per_node",
    "max_nodes_orig","max_nodes","max_oversubscribe","max_share","max_time",
    "mem_per_tres","min_cpus","min_mem_per_cpu","min_mem_per_node","min_nodes_orig",
    "min_nodes","name","network","nice","node_cnt","node_list","nodes",
    "ntasks_per_board","ntasks_per_core","ntasks_per_gpu","ntasks_per_node",
    "ntasks_per_socket","ntasks_per_tres","num_tasks","oversubscribe","pack_job_offset",
    "partition","pn_min_cpus","pn_min_memory","pn_min_tmp_disk","power_flags",
    "priority_job_factor","priority_tier","priority","qos","reboot","req_context",
    "req_nodes","req_switch","requeue","reservation","script","selinux_context",
    "shared","site_factor","sockets_per_board","sockets_per_node","spank_job_env_size",
    "spank_job_env","start_time","state_up","std_err","std_in","std_out",
    "threads_per_core","time_limit","time_min","total_cpus","total_nodes",
    "tres_bind","tres_freq","tres_per_job","tres_per_node","tres_per_socket",
    "tres_per_task","user_id","user_name","users","wait4switch","wckey","work_dir"
  }

  local empty_vars=""
  for _, name in pairs(attr_names) do
    if job_desc[name] ~= nil then
      slurm.log_user("VAR="..name.." val="..tostring(job_desc[name]))
    else
      if empty_vars == "" then
        empty_vars = name
      else
        empty_vars = empty_vars..", "..name
      end
    end
  end
  slurm.log_user("Empty vars: "..empty_vars)

  for part, data in pairs(part_list) do
    for key, val in pairs(data) do
      slurm.log_user(part.." > "..key.." = "..val)
    end
  end
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
function job_info.slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
  if false then -- Set it to 'true' TO GET INFO ABOUT THE JOB
    job_info._job_info(job_desc, part_list, submit_uid) -- luacheck: ignore
  end
  return slurm.SUCCESS
end

-- Called when a job is modified, as in with scontrol
-- Args: TBD (not used yet)
function job_info.slurm_job_modify(job_desc, job_rec, part_list, modify_uid) -- luacheck: ignore
  return slurm.SUCCESS
end
------------------------------------------------------------------------------

-- slurm.log_info("job_info lua plugin loaded")
return job_info
