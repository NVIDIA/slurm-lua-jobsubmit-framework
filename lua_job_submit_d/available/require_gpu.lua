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
----------------------------------------------------------
--
-- Require GPUs for jobs, except non-GPU partitions, reject a job otherwise
--
----------------------------------------------------------

local require_gpu = {
	-- list of partition, we don't require GPUs
	exclude_partitions = {"cpu", "admin", "debug"}
}

function require_gpu.slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
	local tres_vals = {
		tres_per_job = job_desc.tres_per_job or false,
		tres_per_node = job_desc.tres_per_node or false,
		tres_per_socket = job_desc.tres_per_socket or false,
		tres_per_task = job_desc.tres_per_task or false
	}
	local gpu_requested = false

	if not require_gpu.is_partition_exempt(job_desc.partition) then
		for tres_name,tres_value in pairs(tres_vals) do
			if tres_value then
				if string.find(tres_value, "gpu:0") then
					slurm.log_user("You may not submit a job not requesting GPUs in a non-CPU partition. " .. tres_name .. " string: " .. tres_value .. ", partition: " .. job_desc.partition)
					return slurm.ERROR
				end
				if string.find(tres_value, "gpu") then
					gpu_requested = true
				end
			end
		end
		if not gpu_requested then
			slurm.log_user("Cannot find GPU specification, you may not submit a job not requesting GPUs in a non-CPU partition, partition: " .. job_desc.partition)
			return slurm.ERROR
		end
	end
	return slurm.SUCCESS
end

function require_gpu.slurm_job_modify(job_desc, job_rec, part_list, modify_uid) -- luacheck: ignore
	return slurm.SUCCESS
end

function require_gpu.is_partition_exempt(partition)
	for _,part_name in ipairs(require_gpu.exclude_partitions)
	do
		if string.find(partition, part_name) then return true end
	end
	return false
end

return require_gpu
