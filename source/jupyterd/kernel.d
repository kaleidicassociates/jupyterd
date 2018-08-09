module juypterd.kernel;

import jupyterd.message;
import jupyterd.conn;
import juypterd.interpreter;
import std.json;
import std.uuid;
import std.concurrency;
import asdf;
import zmqd : Socket, SocketType, Frame, poll, PollItem, PollFlags;
import core.time;
import std.stdio : writeln;
import drepl.interpreter : InterpreterResult;

//TODOs: add kernel UUID to ZMQ identity for ioPub

//debug = traffic;
//debug = connect;
void startHeartBeat(shared(Socket*) shbs, shared(bool*) run)
{
    import core.thread;
    import core.atomic;
    
    auto hbs = cast(Socket*)shbs;
    ubyte[1024] data;
    while(atomicLoad(run))
    {
        hbs.receive(data[]);
        hbs.send(data[]);
        data[] = 0;
        Thread.getThis().sleep(500.msecs);
    }
}

struct Channel
{
    Socket socket;
    ushort port;
    MessageHeader lastHeader;
    string name;
    this(string n,SocketType t, ushort p)
    {
        name = n;
        socket = Socket(t);
        port = p;
    }
    void bind(const ref ConnectionInfo ci)
    {
        string s = ci.connectionString(port);
        debug(connect) writeln("Binding to: ",s);
        socket.bind(s);
    }
    Message getMessage(string key)
    {
        string[] frames;
        frames.length = 6;
        do {
            auto f = Frame();
            socket.receive(f);
            frames ~= cast(string)f.data.idup;
        } while (socket.more);
        debug(traffic)
        {
            writeln("Recieved on ",name);
            foreach(f;frames)
                writeln("\t\"",f,"\"");
        }
        auto wm = frames.wireMessage;
        auto sig = wm.signature(key);
        writeln("\tSignature match? ", sig ,"\n\t                 ", wm.sig);
        return wm.message();
    }
    void send(string ss, bool more)
    {
        debug(traffic) writeln("\t\"", ss,"\"");
        socket.send(ss,more);
    }
    void send(ref WireMessage wm)
    {
        debug(traffic) writeln("Sending on ",name);
        if (wm.identities)
            foreach(i;wm.identities)
                send(i,/*more=*/true);
        
        string blankIfNull(string s)
        {
            return s ? s : "{}";
        }
        send(WireMessage.delimeter, true);
        send(wm.sig, true);
        send(wm.header,true);
        send(blankIfNull(wm.parentHeader),true);
        send(blankIfNull(wm.metadata) , true);
        send(wm.content,false);
        
        /+
        send(s,wm.content, wm.rawBuffers !is null);
        if (wm.rawBuffers !is null)
        {
            foreach(b;wm.rawBuffers)
            send(b, true);
        }
        send("",false);
        +/
        debug(traffic) writeln("sent.");
    }
}

struct Kernel
{
    enum KernelVersion = "0.1";
    enum protocolVersion = "5.3";
    enum Status
    {
        ok,
        error,
        idle,
        busy
    }

    Channel shell, control, stdin, ioPub, hb;

    string userName, session, key;
    bool infoSet;
    // For keping track of In[n] and Out[n]
    int execCount = 1;
    Tid heartBeat;

    Interpreter interp;
    
    bool running;

    this(Interpreter interpreter, string connectionFile)
    {
        interp = interpreter;
        session = randomUUID.toString;

        import std.file : readText;
        auto ci = connectionFile.readText.deserialize!ConnectionInfo;

        key = ci.key.dup;
        enum shellType = SocketType.router;
        shell   = Channel("shell"  ,shellType, ci.shellPort);
        control = Channel("control",shellType, ci.controlPort);
        stdin   = Channel("stdin"  ,SocketType.router, ci.stdinPort);
        ioPub   = Channel("ioPub"  ,SocketType.pub,    ci.ioPubPort);
        hb      = Channel("hb"     ,SocketType.rep,    ci.hbPort);
        
        debug(connect) writeln("Commencing binding...");
        shell.bind(ci);
        control.bind(ci);
        stdin.bind(ci);
        ioPub.bind(ci);
        hb.bind(ci);
        debug(connect) writeln("... done.");
        running = true;
        heartBeat = spawn(&startHeartBeat, cast(shared(Socket*))(&hb.socket), cast(shared(bool*))&running);
    }
    
    void mainloop()
    {
        while(running)
        {
            PollItem[] items = [
                PollItem(shell.socket, PollFlags.pollIn),
                PollItem(control.socket, PollFlags.pollIn),
            ];

            const n = poll(items, 100.msecs);
            if (n)
            {
                if (items[0].returnedEvents == PollFlags.pollIn)
                    handleShellMessage(shell);
                
                // control is identical to shell but usually recieves shutdown & abort signals
                if (items[1].returnedEvents == PollFlags.pollIn)
                    handleShellMessage(control);
            }
            
            //stdin (the channel) is used for requesting raw input from client.
            //not implemented yet
        
            //ioPub is written to by the handling of the other sockets.
            
            //heartbeat is handled on another thread.
        }
    }
    
    void handleShellMessage(ref Channel c)
    {
        auto m = c.getMessage(key);
        if (!infoSet)
        {
            userName = m.header.userName;
            session = m.header.session;
            infoSet = true;
        }
        publishStatus(Status.busy);
        auto msg = Message(m.header,m.identities,userName,session,protocolVersion);

        switch(m.header.msgType)
        {
            case "execute_request":
            {
                if(executeRequest(msg,m.content))
                {
                    publishStatus(Status.idle);
                    return;
                }
                break;
            }
            case "inspect_request":
            {
                //TODO request info from interpreter
                return;
            }
            case "complete_request":
            {
                //TODO request autocomplete from interpreter
                return;
            }
            case "history_request":
            {
                //TODO request history from interpreter
                return;
            }
            case "is_complete_request":
            {
                //TODO request autocomplete
                return;
            }
            
            //deprecated in jupyter 5.1
            case "connect_request":
            {
                connectRequest(msg);
                break;
            }
            case "comm_info_request":
            {
                //TODO kernel comms
                return;
            }
            case "kernel_info_request":
            {
                kernelInfoRequest(msg);
                break;
            }
            case "shutdown_request":
            {
                shutdownRequest(msg, m.content["restart"] == JSONValue(true));
                break;
            }
            default: return;
        }
        auto wm = msg.wireMessage(key);
        c.send(wm);
        publishStatus(Status.idle);
        
    }
    
    bool executeRequest(ref Message msg, ref JSONValue content)
    {
        msg.header.msgType = "execute_reply";
        const bool silent = content["silent"] == JSONValue(true);

        const history = (content["store_history"] == JSONValue(true)) && silent;
        string code = content["code"].str;
        if (!silent)
        {
            publishInputMsg(code);
        }

        auto res = interp.interpret(code);
        
        const succeded = res.state == InterpreterResult.State.success;

        if (!succeded)
        {
            if (res.state == InterpreterResult.State.incomplete)
            {
                msg.content["ename"]     = "Incomplete request";
                msg.content["evalue"]    = "Incomplete request";
                msg.content["traceback"] = [""];
            }
            else // error
            {
                msg.content["ename"]   = "Error";
                //TODO: create traceback
                msg.content["evalue"]  = res.stdout;
                msg.content["traceback"] = [""];
                
            }
            msg.content["status"] = "error";
            if (res.stderr.length)
                publishStreamText("stderr",res.stderr);
        }
        else
        {
            msg.content["status"] = "ok";
            //if (res.stdout.length)
            //    publishStreamText("stdout",res.stdout);
        }

        msg.content["execution_count"] = execCount;
        publishExecResults(res.stdout);
        if (history && succeded) execCount++;
        return silent;
    }
    

    void shutdownRequest(ref Message msg, bool restart)
    {
        //TODO: Handle restart
        msg.header.msgType = "shutdown_reply";
        running = false;
        msg.content["restart"] = restart;
    }
    
    void kernelInfoRequest(ref Message msg)
    {
        msg.header.msgType = "kernel_info_reply";
        msg.content["protocol_version"] = "5.3.0";
        msg.content["implementation"] = "JupyterD";
        msg.content["implementation_version"] = KernelVersion;
        auto li = interp.languageInfo();
        msg.content["language_info"] = ["name" : li.name,
                                        "version" : li.languageVersion,
                                        "mimetype" : li.mimeType,
                                        "file_extension" :li.fileExtension];

    }
    
    void connectRequest(ref Message msg)
    {
        msg.header.msgType = "connect_reply";
        msg.content["shell_port"]   = shell.port;
        msg.content["iopub_port"]   = ioPub.port;
        msg.content["stdin_port"]   = stdin.port;
        msg.content["hb_port"]      = hb.port;
        msg.content["control_port"] = control.port;
    }
    
    Message newIOPubMsg(string hdrName)
    {
        auto m = Message(ioPub.lastHeader,["kernel."~session~"." ~ hdrName],userName,session,protocolVersion);
        m.header.msgType = hdrName;
        return m;
    }
    
    void sendIOPubMsg(ref Message msg)
    {
        auto wm = msg.wireMessage(key);
        ioPub.send(wm);
        ioPub.lastHeader = msg.header;
    }
    
    void publishExecResults(string stdout)
    {
        auto msg = newIOPubMsg("execute_result");
        msg.content["execution_count"] = execCount;
        msg.content["data"] = ["text/plain" : stdout];
        string[string] dummy;
        msg.content["metadata"] = dummy;
        sendIOPubMsg(msg);
        
    }
    
    void publishStreamText(string stream, string text)
    {
        auto msg = newIOPubMsg("stream");
        msg.content["name"] = stream;
        msg.content["text"] = text;
        sendIOPubMsg(msg);
    }

    void publishStatus(Status status)
    {
        auto msg = newIOPubMsg("status");
        import std.conv : to;
        msg.content["execution_state"] = status.to!string;

        sendIOPubMsg(msg);
    }
    
    void publishInputMsg(string code)
    {
        auto msg = newIOPubMsg("execute_input");
        msg.content["code"] = code;
        msg.content["execution_count"] = execCount;
        sendIOPubMsg(msg);
    }
}

//MASSIVE HACK: allow compiling on OSX for testing echo engine
version(OSX)
extern(C) void* rt_loadLibrary(const char* name)
{
    return null;
}
