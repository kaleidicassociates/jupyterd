module jupyterd.message;

import asdf;
import std.json;

import std.string : representation;
import std.digest.hmac;
import std.digest.sha;

import std.stdio : writeln; //Debugging

/// MessageHeader encodes header info for ZMQ messages.
struct MessageHeader
{
    @serializationKeys("msg_id")
    string msgID;
    
    @serializationKeys("username")
    string userName;
    
    @serializationKeys("session")
    string session;
    
    @serializationKeys("msg_type")
    string msgType;
    
    @serializationKeys("version")
    string protocolVersion;
    
    @serializationKeys("date")
    string timestamp;
}

struct Message
{
    string[] identities;
    MessageHeader header;
    MessageHeader parentHeader;
    JSONValue metadata;
    JSONValue content;
    this(MessageHeader parent,string[] ids,string userName,string session,string protocolVersion)
    {
        import std.datetime.date;
        import std.datetime.systime;
        import std.uuid;
        identities = ids;
        parentHeader = parent;
        header.userName = userName;
        header.session = session;
        header.protocolVersion = protocolVersion;
        header.timestamp = (cast(DateTime)Clock.currTime()).toISOExtString();
        header.msgID = randomUUID().toString;
    }
    this(WireMessage wire)
    {
        identities = wire.identities;
        header = parseHeader(wire.header);
        parentHeader = parseHeader(wire.parentHeader);
        metadata = wire.metadata.parseJSON;
        content  = wire.content.parseJSON;
    }
}
MessageHeader parseHeader(string j)
{
    MessageHeader mh;
    if (j == "{}")
        return mh;
    auto vv = parseJSON(j);
    auto v = vv.object;
    
    mh.msgID            = v["msg_id"].str;
    mh.userName         = v["username"].str;
    mh.session          = v["session"].str;
    mh.msgType          = v["msg_type"].str;
    mh.protocolVersion  = v["version"].str;
    mh.timestamp        = v["date"].str;
    return mh;
    
}
Message message(WireMessage wm)
{
    return Message(wm);
}

struct WireMessage
{
    private import std.digest.sha;
    string[] identities;
    enum delimeter = "<IDS|MSG>";
    string sig; //HMAC signature
    string header;
    string parentHeader;
    string metadata;
    string content;
    string[] rawBuffers;
    
    this(string[] msgs)
    {
        int i = 0;
        
        while(msgs[i] != delimeter) i++; // find delimeter
        int j = 0;
        while (msgs[j].length == 0) j++;
        identities = msgs[j .. i];

        
        i++; // Skip delimeter
        
        sig          = msgs[i++];
        header       = msgs[i++];
        parentHeader = msgs[i++];
        metadata     = msgs[i++];
        content      = msgs[i++];
        rawBuffers   = msgs[i .. $];
    }
    
    this(Message m, string key)
    {
        import std.digest : hexDigest;
        identities = m.identities;
        

        header = m.header.serializeToJson;
            
        if (m.parentHeader.msgID is null)
            parentHeader = "{}";
        else
            parentHeader = m.parentHeader.serializeToJson;
            
        if(m.metadata == JSONValue(null))
            metadata = "{}";
        else
            metadata = m.metadata.toString;
            
        content = m.content.toString;
        sig = signature(key);
        
    }

    string signature(string key)
    {
        import std.meta : AliasSeq;
        auto mac = hmac!SHA256(key.representation);
        foreach(w;AliasSeq!(header,parentHeader,metadata,content))
            mac.put(w.representation);
        ubyte[32] us = mac.finish;
        import std.array : appender;
        import std.conv : toChars;
        auto cs = appender!string;
        cs.reserve(64);
        
        foreach(u;us[])
        {
            cs.put(toChars!16(cast(uint)u));

        }
        return cs.data.idup;
    }
}

WireMessage wireMessage(string[] msgs)
{
    return WireMessage(msgs);
}

WireMessage wireMessage(Message m, string key)
{
    return WireMessage(m,key);
}

