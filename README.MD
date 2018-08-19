JupyterD
========

A Jupyter Notebook kernel written in D.

Currently supports an echo "interpreter" and D Repl.
Tested on Arch Linux; should work on other distributions and Windows with minor changes.

To install run ./install.sh
This copies the executable jupyterd to /usr/sbin (you need sudo) and makes a directory
/usr/share/jupyter/kernels/d/ and copies the kernel.json file to this directory.  Change the argv
argument in kernel.json from d to echo if you wish to switch to the echo interpreter.

Then just run `jupyter notebook` and create a new notebook using the d kernel.

Wait for the kernel to come online - it can take a while (needs to be fixed).

Kernel imports all of phobos using std.experimental.all.

It's pre-alpha, just a bare proof of concept right now.

The existing D repl was written for the commandline and probably you will encounter difficulties running it in a notebook
environment.


Other projects - see pydmagic by John Colvin



To Do
=====
* Make it work as you would expect a kernel to in any language
* Add HTML and markdown table output to display arrays of structs or of dicts in a useful manner
* Integrate with mir and other numeric libraries
* Integrate with charting
* Consider adding to Dlang tour and run.dlang.io when stable
* Integrate with dpp
* Integrate with dub



