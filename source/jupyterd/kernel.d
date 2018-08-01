module juypterd.kernel;

import jupyterd.message;
import jupyterd.conn;
import juypterd.interpreter;
import std.json;
import std.uuid;
import std.concurrency;
import asdf;
import zmqd : Socket, SocketType, Frame;
import std.stdio : writeln;

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
    Message getMessage()
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
        return frames.wireMessage.message();
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
    int execCount = 0;
    Tid heartBeat;

    Interpreter interp;
    
    bool running;

    this(Interpreter interpreter, string connectionFile)
    {
        interp = interpreter;
        session = randomUUID.toString;

        import std.file : readText;
        auto ci = connectionFile.readText.deserialize!ConnectionInfo;

        key = ci.key;
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
            handleShellMessage(shell);
        
            // control is identical to shell but usually recieves shutdown & abort signals
            handleShellMessage(control);
            
            //stdin (the channel) is used for requesting raw input from client.
            //not implemented yet
        
            //ioPub is written to by the handling of the other sockets.
            
            //heartbeat is handled on another thread.
        }
    }
    
    void handleShellMessage(ref Channel c)
    {
        auto m = c.getMessage();
        if (!infoSet)
        {
            userName = m.header.userName;
            session = m.header.session;
            infoSet = true;
        }
        auto msg = Message(m.header,m.identities,userName,session,protocolVersion);
        publishStatus(Status.busy);
        switch(m.header.msgType)
        {
            case "execute_request":
            {
                executeRequest(msg,m.content);
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
    
    void executeRequest(ref Message msg, ref JSONValue content)
    {
        msg.header.msgType = "execute_reply";
        const silent = content["silent"] == JSONValue(true);
        content["store_history"] = (content["store_history"] == JSONValue(true)) && silent;
        string code = content["code"].str;
        if (!silent)
        {
            publishStatus(Status.busy);
            publishInputMsg(code);
        }
        const bool hasCode = code.length == 0;
        string res;
        auto status = hasCode ? interp.interpret(content["code"].str,res) : Status.ok;
        if (!silent) publishStatus(Status.idle);
        import std.conv : to;
        msg.content["status"] = status.to!string;
        msg.content["execution_count"] = execCount++;
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
    void publishStreamText(string stream, string text)
    {
        auto msg = Message(ioPub.lastHeader,null,userName,session,protocolVersion);
        msg.header.msgType = "stream";
        msg.content["name"] = stream;
        msg.content["text"] = text;
        auto wm = msg.wireMessage(key);
        ioPub.send(wm);
        ioPub.lastHeader = msg.header;
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

    void publishStatus(Status status)
    {
        auto msg = Message(ioPub.lastHeader,null,userName,session,protocolVersion);
        msg.header.msgType = "status";
        import std.conv : to;
        msg.content["status"] = status.to!string;

        auto wm = msg.wireMessage(key);
        ioPub.send(wm);
        ioPub.lastHeader = msg.header;
    }
    
    void publishInputMsg(string code)
    {
        auto msg = Message();
        msg.parentHeader = ioPub.lastHeader;
        msg.content["code"] = code;
        msg.content["execution_count"] = execCount;
        auto wm = msg.wireMessage(key);
        ioPub.send(wm);
        ioPub.lastHeader = msg.header;
    }
}

//MASSIVE HACK: allow compiling on OSX for testing echo engine
version(OSX)
extern(C) void* rt_loadLibrary(const char* name)
{
    return null;
}
