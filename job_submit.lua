-- luacheck: std lua51
-- luacheck: allow defined top
-- luacheck: globals slurm modules_dir

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
-- Load all lua files under special directory
--
-- WARNING!!! No checks! Any bad file can fail entire plugin
--

modules_dir = "/etc/slurm/lua_job_submit_d"
-- lua_mod_dir = "etc.slurm.lua_job_submit_d."
lua_mod_dir = ""
-- modules_dir = "./tst"
package.path = package.path .. ";" .. modules_dir.."/?.lua"

function slurm_job_action(action, job_desc, job_rec, part_list, submit_uid) -- luacheck: ignore
    local h = io.popen("ls -1 "..modules_dir.."/*.lua")
    local data = h:read("*all")
    local ret
    h:close()
    local lst = {}
    for i in data:gmatch("[^\r\n]+") do
        table.insert(lst,i)
    end

    for _,fname in pairs(lst) do
        local _, _, modname = string.find(fname, "([0-9a-zA-Z_-]+).lua$")
        if modname ~= nil then
            slurm.log_info("start: "..modname)
            local m=require(lua_mod_dir..modname)
            if action == "submit" then
              ret = m.slurm_job_submit(job_desc, part_list, submit_uid)
            else
              slurm.log_info("check "..modname)
              ret = m.slurm_job_modify(job_desc, job_rec, part_list, submit_uid)
              slurm.log_info("ret="..ret.." succes=("..slurm.SUCCESS..")")
            end
            if ret ~= slurm.SUCCESS then
                return ret
            end
            slurm.log_info("end  : "..modname.."=".. ret)
        else
            slurm.log_info("Bad module name: "..fname..". Ignoring. Please send this to admins")
        end
    end
    return slurm.SUCCESS
end

function slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
  return slurm_job_action('submit', job_desc, nil, part_list, submit_uid)
end

-- Called when a job is modified, as in with scontrol
-- Args: TBD (not used yet)
function slurm_job_modify(job_desc, job_rec, part_list, modify_uid) -- luacheck: ignore
  return slurm_job_action('modify', job_desc, job_rec, part_list, modify_uid)
end

-- slurm_job_submit({},0,0)
