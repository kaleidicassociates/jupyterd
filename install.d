#!/usr/bin/rdmd

import std.stdio;
import std.getopt;
import std.exception : enforce;
import std.array : empty, front, popFront;
import std.process : execute;

string jdir = "/usr/local/bin/";

string getKernelPath() {
	import std.algorithm : splitter, startsWith;
	import std.string : strip, splitLines;

	auto jp = execute(["jupyter", "kernelspec", "list"]);
	enforce(jp.status == 0, "Failed to quere jupyter for the kernelspecs");

	auto sout = jp.output.splitLines;

	/* transform output of form
	Available kernels:
  	  python2    /usr/local/share/jupyter/kernels/python2

	into: /usr/local/share/jupyter/kernels/
	*/

	if(sout.startsWith("Available kernels:")) {
		sout.popFront();
	} else {
		throw new Exception("No available kernels found");
	}

	while(!sout.empty) {
		enum p = "python2";
		string f = sout.front.strip();
		if(f.startsWith(p)) {
			f = f[p.length .. $].strip();
			f = f[0 .. $ - p.length];
			return f;
		}
		sout.popFront();
	}
	throw new Exception("python2 kernel path not found");
}

void installJupyterd(const string kernelPath, const bool build) {
	import std.file : exists, mkdir, copy, isDir, isFile;

	const ddir = kernelPath ~ 'd';
	if(!exists(ddir)) {
		mkdir(ddir);
	}

	enum k = "kernel.json";
	enforce(isFile(k), "kernel.json not found in pwd");
	auto g = execute(["cp", k, ddir]);

	enum j = "jupyterd";
	if(!exists(j) || build) {
		auto e = execute(["dub", "build"]);
		writeln(e.output);
	}

	auto f = execute(["cp", j, jdir]);
}

void removeJupyterd(const string kernelPath) {
	import std.file : rmdir, copy, isFile;

	const ddir = kernelPath ~ "d/";
	const k = ddir ~ "kernel.json";
	enforce(isFile(k), "kernel.json not found in " ~ ddir);

	auto g = execute(["rm", k]);
	rmdir(ddir);

	const l = jdir ~ "jupyterd";
	enforce(isFile(l), "jupyterd not found in " ~ jdir);
	g = execute(["rm", l]);
}

int main(string[] args) {
	bool install;
	bool remove;
	bool path;
	bool build;

	auto helpInformation = getopt(args,
			"install|i", "install or update the D Jupyter Kernel", &install,
			"remove|r", "remove the D Jupyter Kernel", &remove,
			"build|b", "force jupyterd build", &remove,
			"path|p", "display the path where Jupyter Kernel are installed",
				&path
		);
	if(helpInformation.helpWanted) {
		defaultGetoptPrinter("Installer for the D Jupyter Kernel.\n"
			~ "This needs to be executed with root privileges.",
			helpInformation.options);
		return 1;
	}

	string ppath = getKernelPath();
	if(path) {
		writefln!"python2 kernel path: '%s'"(ppath);
	}

	if(install) {
		installJupyterd(ppath, build);
		return 0;
	} else if(remove) {
		removeJupyterd(ppath);
		return 0;
	}

	return 0;
}
