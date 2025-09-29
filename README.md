# SLURM lua jobsubmit mini-framework

This mini-framework allows you to have several lua scripts,
running as a one jobsubmit SLURM plugin. The idea is simple:
each script is a lus module and is just loaded by the framework script,
then executed. The first fail stops the checks execution chain.
Modules are loading in an alphabetical order from `/etc/slurm/lua_job_submit_d`.

## Pre-requisites

1. SLURM, compiled with lua support
2. lua compiler and runtime v5.1 or higher on the SLURM controllers (lua-posix and lua-filesystem are required)

## How to install

1. Copy `lua_job_submit_d` dir, `job_submit.lua` and `lua.conf` into
   `/etc/slurm` dir.
2. Add content of `slurm.conf-addition` into your `/etc/slurm/slurm.conf`
3. Optionally enable any of scripts in `/etc/slurm/lua_job_submit_d/available`,
   running `cd /etc/slurm/lua_job_submit_d; ln -s available/THE_SCRIPT_YOU_WANT.lua .`
4. Or put your own!
5. Restart slurm service or run `scontrol reconfigure`.

## Available example modules

### enrich_comments.lua

Adds information to admin_comments field. In this example we add info about dependencies, network and switches.

### gpu_features.lua

Enable GPU/IB features like MIG, GSP, and SHARP if they are requested (via --feature or --network).

### job_info.lua

Debug module - prints the job attributes, available via slurm. Please, check which attributes are available in YOUR SLURM version, they may differ.

### require_account.lua

Force user to specify account name, no default accounts are allowed.

### require_gpu.lua

Require GPUs for jobs, except non-GPU partitions, reject a job otherwise.

### restrict_interactive.lua

This plugin forbids running or restricts max time for batch jobs in interactive partitions.
List of such partitions is specified in file `/etc/slurm/interactive_partitions`.
The list is cached, in case you need to reload it, touch the file `/etc/slurm/interactive_partitions.update`.

Filenames are tunable - see `restrict_interactive` definition
"update" file path is made of `interactive_partitions` file plus `.update`

File format:
```text
partition = -  #<- forbid any batch job in "partition"
partition = 10 #<- max time = 10 minutes in "partition"
DEFAULT = 20   #<- max time (or - for forbid) for DEFAULT partition
               # THIS ENTRY WORKS IN CASE WHEN `-p` IS NOT USED. E.g.: `sbatch --wrap hostname`
__debug__=1    #<- increase debug logging level
```

## How to write a module

Use the simple script below as a starter. Refer to scripts in `available` dir as a reference.
It is also recommended to put scripts into `available` dir and create symlinks to
those you really need. Remember, all modules should have `.lua` extention.

```lua
-- luacheck: std lua51
-- luacheck: allow defined top
-- luacheck: globals slurm _
------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- Don't use any local functions, they can interfere with other modules
-- All functions SHOULD be module members

-- THIS IS A MODULE OBJECT
local my_module = {}

-- A local function example
function my_module._local_function(job_desc, part_list, submit_uid) -- luacheck: ignore

  slurm.log_user("Hello from slurm jobsubmit lua plugin!")

end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
-- Slurm job_submit plugin entrypoints
--
-- Called when a job is submitted
-- Args:
--   job_desc   - table containing details of the submitted job. We can both read
--                and modify these values before the job goes into the queue
--   part_list  - list of tables corresponding to partitions available to the
--                job (untested)
--   submit_uid - Unix user ID of the user submitting the job (untested)
function my_module.slurm_job_submit(job_desc, part_list, submit_uid) -- luacheck: ignore
  -- You can run any nessessary code here.
  -- job_info.lua is a good source of infromation you can get from the job_desc
  my_module._local_function(job_desc, part_list, submit_uid)
  return slurm.SUCCESS
end

-- Called when a job is modified, as in with scontrol
-- Args:
--   job_desc   - table containing details of the update
--   job_rec    - table containing details of the current job
--   part_list  - list of tables corresponding to partitions available to the
--                job (untested)
--   modify_uid - Unix user ID of the user submitting the job (untested)
function my_module.slurm_job_modify(job_desc, job_rec, part_list, modify_uid) -- luacheck: ignore
  return slurm.SUCCESS
end
------------------------------------------------------------------------------

-- slurm.log_info("my_module lua plugin loaded")

-- THIS IS A MOST IMPORTANT PART: RETURN THE MODULE OBJECT
return my_module
```

## How to contribute

Just make a Pull/Merge request!

## How to test

Oh... It is a kind of not easy. I use slurm-docker-testing-cluster project, but if you can spin up a local SLURM installation it also works.

