-- SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
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
-- Auto onboarding to Slurm accounts.
-- Uses ~/.onboarded_to_slurm file to check if the user is onboarded to Slurm.
-- Uses /etc/slurm/onboard_map file for UNIX group and SLURM account mapping.
-- If the file exists, read its content, and get list of accounts, use onboarded into.
-- If account requested by user is not in the list, check if the user is in a group,
-- matching account.
--   If yes, create a user account in Slurm and update the flag file.
-- If the file does not exist, check if the user is in any allowed group in map file.
--   If yes, create a user account in Slurm and the flag file.
--   If the user is not in any allowed group, the job is rejected with 
--   ESLURM_INVALID_ACCOUNT error.
--
-- Usage:
--   Copy this code into /etc/slurm/lua_job_submit_d/auto_onboard.lua
--   Use modular lua job_submit plugin to load this code. (https://github.com/NVIDIA/slurm-lua-jobsubmit-framework)
--   Add the following to /etc/slurm/onboard_map:
--     group1=account1
--     group2=account2
--     ...
--   Restart Slurm.

-- Plugin local config
local auto_onboard = {
  prefix='/usr/bin',             -- prefix for slurm commands
  home_dir='/home',              -- home directory path
  debug=false,                   -- debug mode (true/false)
  map_file='/etc/slurm/onboard_map',  -- group->account mapping file
  account_map={},                -- loaded from map_file, do not pre-fill!
}

------------------------------------------------------------------------------
------------------------------------------------------------------------------
--
-- Simple set operations (sets are tables with keys as elements, values as true)
--

local Set = {}
Set.__index = Set

-- Check if an element is in a set
function Set.contains(s, elem)
  return s[elem] ~= nil
end

-- Convert a set to string representation
function Set.__tostring(s)
  local items = {}
  for k in pairs(s) do
    table.insert(items, tostring(k))
  end
  table.sort(items)
  return "{" .. table.concat(items, ", ") .. "}"
end

-- Create a set from a table/array
function Set.new(t)
  local s = {}
  setmetatable(s, Set)
  for _, v in pairs(t or {}) do
    s:add(v)
  end
  return s
end

-- Add an element to a set
function Set.add(s, elem)
  s[elem] = true
end

-- Delete an element from a set
function Set.del(s, elem)
  s[elem] = nil
end

-- Union: elements in either A or B
function Set.union(a, b)
  local result = Set.new()
  for k in pairs(a) do result:add(k) end
  for k in pairs(b) do result:add(k) end
  return result
end

-- Intersection: elements in both A and B
function Set.intersection(a, b)
  local result = Set.new()
  for k in pairs(a) do
    if b:contains(k) then result:add(k) end
  end
  return result
end

-- Subtraction (difference): elements in A but not in B
function Set.subtract(a, b)
  local result = Set.new()
  for k in pairs(a) do
    if not b:contains(k) then result:add(k) end
  end
  return result
end

-- Load account_map from file (format: group=account per line)
function auto_onboard.load_account_map()
  local f = io.open(auto_onboard.map_file, "r")
  if f == nil then
    return false
  end
  auto_onboard.account_map = {}
  for line in f:lines() do
    -- Skip empty lines and comments
    if line:match("^%s*[^#]") then
      local group, account = line:match("^%s*([^=%s]+)%s*=%s*([^%s]+)")
      if group and account then
        auto_onboard.account_map[group] = account
      end
    end
  end
  f:close()
  return true
end

-- Call a command and return the status code and result
function auto_onboard.call_command(command)
  local pipe = io.popen(command, "r")
  local result = pipe:read("*all")
  local status = pipe:close()
  return tostring(status), tostring(result)
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
function auto_onboard.slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
  local user_name = job_desc['user_name']
  local user_home = auto_onboard.home_dir..'/'..user_name
  local user_account = job_desc['account']
  local status, user_groups, f
  local onboarded_accounts = Set.new()
  local accounts_to_onboard = Set.new()
  local result -- luacheck: ignore

  if user_name == nil then
    slurm.log_user("User not found. Are you onboarded?")
    return slurm.ESLURM_INVALID_ACCOUNT
  end

  -- Check if user is already onboarded
  f=io.open(user_home.."/.onboarded_to_slurm","r")
  if f~=nil then
    for line in f:lines() do
      onboarded_accounts:add(line)
    end
    f:close()
    if onboarded_accounts:contains(user_account) then
      if auto_onboard.debug then
        slurm.log_user("User "..user_name.." is already onboarded to account "..user_account)
      end
      return slurm.SUCCESS
    end
  end

  -- Get user groups
  status, user_groups = auto_onboard.call_command("id -Gn "..user_name)
  if status ~= "true"  then
    slurm.log_user("Failed to get user groups: "..status)
    return slurm.ESLURM_INVALID_ACCOUNT
  end

  -- Load the map on module load
  auto_onboard.load_account_map()

  -- Get list of accounts the user SHOULD be onboarded to
  for group in user_groups:gmatch("%s+([^%s]+)") do
    if auto_onboard.account_map[group] then
      accounts_to_onboard:add(auto_onboard.account_map[group])
    end
  end

  -- Onboard user into missing accounts
  local missing_accounts = Set.subtract(accounts_to_onboard, onboarded_accounts)
  if auto_onboard.debug then
    slurm.log_user("Onboarding user "..user_name.." to accounts: "..
      tostring(onboarded_accounts).." -> "..
      tostring(accounts_to_onboard).." missing: "..tostring(missing_accounts).."\n")
  end
  local missing_accounts_list = ""
  for account in pairs(missing_accounts) do
    missing_accounts_list = missing_accounts_list..account..","
  end
  local onboard_command = auto_onboard.prefix.."/sacctmgr add -i user name="..user_name..
                          " account="..missing_accounts_list
  if auto_onboard.debug then
    slurm.log_user("Onboarding command: "..onboard_command)
  end
  status, result = auto_onboard.call_command(onboard_command)
  if status ~= "true" then
    slurm.log_user("Failed to onboard user: "..result.." (status: "..status..")")
    -- return slurm.ESLURM_INVALID_ACCOUNT
  end
  -- for account in pairs(missing_accounts) do
  --   if auto_onboard.debug then
  --     slurm.log_user("Creating user account: "..account)
  --   end
  --   status, result = auto_onboard.call_command( -- luacheck: ignore
  --     auto_onboard.prefix.."/sacctmgr -i create user name="..user_name.." account="..account)
  --   os.execute("sleep 1") -- wait for the account to be created
  --   if auto_onboard.debug then
  --     if status ~= "true" then
  --       slurm.log_user("Failed to create user account: "..result.." (status: "..status..")")
  --     end
  --   end
  -- end

  f = io.open(user_home.."/.onboarded_to_slurm","w")
  if f == nil then
    if auto_onboard.debug then
      slurm.log_user("Failed to create onboarded file: "..user_home.."/.onboarded_to_slurm")
    end
  end
  for account in pairs(missing_accounts) do
    f:write(account.."\n")
  end
  f:close()
  return slurm.SUCCESS
end
------------------------------------------------------------------------------

-- slurm.log_info("auto_onboard lua plugin loaded")
return auto_onboard
