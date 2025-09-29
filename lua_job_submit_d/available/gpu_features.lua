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
-- luacheck: std lua51
-- luacheck: allow defined top
-- luacheck: globals slurm _
---------------------------------------------------------------------
--
-- Enable IB/GPU features
--
---------------------------------------------------------------------

local gpu_features = {
    -- Default GPU features
    _GPU_F_DEFAULT_FEATURES = {["mig"] = "off", ["gsp"] = "off"},

    -- List of partitions, which can use SHARP
    _GPU_F_SHARP_PARTITIONS = {["with-sharp"] = true, ["interactive"] = true},

    -- flag file for disabling sharp globally
    _GPU_F_SHARP_FLAG_FILE = "/etc/slurm/sharp-disabled",

    -- List of partitions, which can use SHARP
    _GPU_F_GSP_ACCOUNTS = {["admin"] = true}

}

function gpu_features.file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

function gpu_features.slurm_job_submit(job_desc, part_list, submit_uid)
    -- Store --network flag in admin_comment so it's accessible from sacct records
    if job_desc.network then
        -- Store --network flag in admin_comment so it's accessible from sacct records
        local c = "network=" .. job_desc.network
        if job_desc.admin_comment then
            job_desc.admin_comment = job_desc.admin_comment .. "," .. c
        else
            job_desc.admin_comment = c
        end

        if job_desc.network == "sharp" then
            -- Block sharp jobs if this file exists
            if gpu_features.file_exists(gpu_features._GPU_F_SHARP_FLAG_FILE) then
                slurm.log_user("ERROR: SHARP is currently disabled")
                return slurm.ESLURM_ACCESS_DENIED
            end

            local partition = job_desc.partition
            -- Find which partition is the default one if needed.
            if partition == nil then
                for name, part in pairs(part_list) do
                    if part.flag_default == 1 then
                        partition = name
                        break
                    end
                end
            end
            -- Multiple partitions can be specified for a job.
            for p in string.gmatch(partition, '([^,]+)') do
                if not gpu_features._GPU_F_SHARP_PARTITIONS[p] then
                    slurm.log_user("ERROR: SHARP cannot be used on the %s partition", p)
                    return slurm.ESLURM_ACCESS_DENIED
                end
            end
        end
    end

    -- Cleanup "--constraints="
    local current_features = ""
    if job_desc.features then
        current_features = job_desc.features
    end
    local overridden_features = {}
    for feature in string.gmatch(current_features, '([^,]+)') do
        local i, j = string.find(feature, '=')
        if i and i > 1 then
            local feature_key = string.sub(feature, 0, i-1)
            local feature_value = string.sub(feature, i+1, -1)

            if feature_key == "mig" and feature_value == "on" then
                if job_desc.max_nodes ~= (2^32 - 2) and job_desc.max_nodes > 1 then
                    slurm.log_user("Can't request MIG to be enabled for a multi-node job. Number of nodes requested: %s", job_desc.max_nodes)
                    return slurm.ESLURM_ACCOUNTING_POLICY
                end
            end

            if feature_key == "gsp" and feature_value == "on" then
                if job_desc.max_nodes ~= (2^32 - 2) and job_desc.max_nodes > 16 then
                    if job_desc.account ~= "admin" then
                        slurm.log_user("Can't request GSP RM to be enabled for more than 16 nodes. Number of nodes requested: %s", job_desc.max_nodes)
                        return slurm.ESLURM_ACCOUNTING_POLICY
                    end
                end
            end

            if gpu_features._GPU_F_DEFAULT_FEATURES[feature_key] ~= nil then
                overridden_features[feature_key] = 1
            end
        end
    end
    for default_key, default_value in pairs(gpu_features._GPU_F_DEFAULT_FEATURES) do
        if not overridden_features[default_key] then
            local addition = ""
            addition = addition .. default_key .. '=' .. default_value
            if string.len(current_features) > 0 then
                addition = ',' .. addition
            end
            current_features = current_features .. addition
        end
    end
    if string.len(current_features) and (not job_desc.features or job_desc.features ~= current_features) then
        job_desc.features = current_features
    end

    return slurm.SUCCESS
end

function gpu_features.slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
    return slurm.SUCCESS
end

return gpu_features

-- return slurm.SUCCESS
