#!/usr/bin/env rdmd

import std.stdio;
import std.file;
import std.path;
import std.exception;
import std.process;
import std.format;
import std.conv;

const auto SRC_GET_NAMES = ["dmd", "druntime", "phobos", "tools", "dub"];
const auto SRC_BUILD_NAMES = ["dmd", "druntime", "phobos", "tools"];
const string ENV_ENABLER_FILE_NAME = ".dlang_enable_bash_environment";

void isDirOk(string path)
{
	chdir(path);
}

void renewRepo(string path, string name, string url)
{
	Exception err;
	
	string bp_p_n = buildPath(path,name);
	
	bool makeClone;
	bool makePull;
	
	writeln("checking ",bp_p_n);
	err = collectException(isDirOk(bp_p_n));
	if (err !is null)
	{
		writeln("   error. trying to recreate (clone will be done on success)");
		makeClone = true;
		collectException(mkdir(bp_p_n));
		err = collectException(isDirOk(bp_p_n));
		if (err !is null)
		{
			throw err;
		}
	} else {
		writeln("  ok. going to pull updates");
		makePull = true;
	}
	
	if (makeClone)
	{
		chdir(bp_p_n);
		writeln("clonning ", url, " to ", bp_p_n);
		auto pid = spawnProcess(["git", "clone", url, "."]);
		if (wait(pid) != 0)
		{
			throw new Exception("error clonning "~ url);
		}
		writeln("  ok");
	}
	
	if (makePull)
	{
		chdir(bp_p_n);
		auto pid = spawnProcess(["git", "checkout", "-f", "master"]);
		if (wait(pid) != 0)
		{
			throw new Exception("error checking out master at "~ bp_p_n);
		}
		
		writeln("pulling ", url, " to ", bp_p_n);
		pid = spawnProcess(["git", "pull"]);
		if (wait(pid) != 0)
		{
			throw new Exception("error pulling updates for "~ name);
		}
		writeln("  ok");
	}
	
}

void renewRepos(string path)
{
	foreach (v; SRC_GET_NAMES)
	{
		renewRepo(path, v, r"https://github.com/dlang/"~v);
	}
}

void buildTargetPrepareClones(
	string src_root_dir,
	string target_root_dir,
	string target
	)
{
	foreach(v; SRC_BUILD_NAMES)
	{
		auto td = buildPath(target_root_dir, v);
		collectException(rmdirRecurse(td));
		collectException(mkdirRecurse(td));
		chdir(td);
		
		auto pid = spawnProcess(["git", "clone", buildPath(src_root_dir, v), "."]);
		if (wait(pid) != 0)
		{
			throw new Exception("Couldn't clone source here: " ~ td);
		}
		
		pid = spawnProcess(["git", "checkout", target]);
		if (wait(pid) != 0)
		{
			throw new Exception("Couldn't checkout "~ target~ " at "~ td);
		}
	}
}

void buildDMD(
	string target_root_dir
	)
{
	auto tdmd = buildPath(target_root_dir, "dmd");
	// auto tlocal = buildPath(target_root_dir, "_local");
	
	chdir(tdmd);
	{
		auto pid = spawnProcess(["dmd", "src/build.d"]);
		if (wait(pid) != 0)
		{
			throw new Exception("Couldn't build source here: " ~ tdmd);
		}
	}
	
	{
		auto pid = spawnProcess(["./build"]);
		if (wait(pid) != 0)
		{
			throw new Exception("Couldn't build source here: " ~ tdmd);
		}
	}
	
	/* pid = spawnProcess(
	["rdmd", "src/build.d",
	"install", "INSTALL="~tlocal]
	);
	if (wait(pid) != 0)
	{
	throw new Exception("Couldn't install dmd here: " ~ tlocal);
	}	 */
	
}

void buildPhobos(
	string target_root_dir
	)
{
	auto tphobos = buildPath(target_root_dir, "phobos");
	
	chdir(tphobos);
	auto pid = spawnProcess(["make", "-f", "posix.mak"]);
	if (wait(pid) != 0)
	{
		throw new Exception("Couldn't build source here: " ~ tphobos);
	}
}

void buildTools(
	string target_root_dir
	)
{
	auto tphobos = buildPath(target_root_dir, "tools");
	
	chdir(tphobos);
	auto pid = spawnProcess(["make", "-f", "posix.mak"]);
	if (wait(pid) != 0)
	{
		throw new Exception("Couldn't build source here: " ~ tphobos);
	}
}

void buildTarget(
	string src_root_dir,
	string target_root_dir,
	string target
	)
{
	buildTargetPrepareClones(
		src_root_dir,
		target_root_dir,
		target
		);
	
	buildDMD(target_root_dir);
	buildPhobos(target_root_dir);
	buildTools(target_root_dir);
	// // buildDUB(target_root_dir);
	createBashSourceScript(target_root_dir);
	
}

void createBashSourceScript(string target_root_dir)
{
	auto txt =
	q"<#!/bin/bash

DLANG_PATH='%1$s/dmd/generated/linux/release/64:%1$s/tools/generated/linux/64'

export PATH="$DLANG_PATH:"$PATH

unset DLANG_PATH
>".format(target_root_dir);
	
	auto fn = chainPath(expandTilde("~"), ENV_ENABLER_FILE_NAME);
	auto f = File(fn, "w");
	scope(exit) f.close();
	f.write(txt);
	
	setAttributes(fn, octal!700);
}


void main(string[] args)
{
	auto wd = expandTilde("~/dlang");
	
	writeln("UPDATING:");
	writeln("==============================");
	renewRepos(wd);
	writeln("==============================");
	
	string target;
	
	if (args.length > 1)
	{
		target = args[1];
	}
	
	if (target == "")
	{
		writeln("target not selected. exiting.");
		return;
	}
	
	writeln("selected target: ", target);
	
	auto wd_target = buildPath(wd, "d_"~target);
	// auto wd_result = buildPath(wd, "d_"~target~"_built");
	
	buildTarget(wd, wd_target, target);
	
}
