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
---------------------------------------------------------------------
--
-- Force user to specify account name, no default accounts are allowed
--
---------------------------------------------------------------------
local require_account = {}

function require_account.slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
    -- Error if account not set
    if not job_desc.account then
        slurm.log_user("You forgot to specify which account you want to use.")
        slurm.log_user("You can get the list of accounts which you have access to runnign this:")
        slurm.log_user(" sacctmgr -nP show assoc where user=$(whoami) format=account")
        return slurm.ESLURM_INVALID_ACCOUNT
    end

    return slurm.SUCCESS
end

function require_account.slurm_job_modify(job_desc, job_rec, part_list, modify_uid) -- luacheck: ignore
    return slurm.SUCCESS
end

return require_account

-- return slurm.SUCCESS
