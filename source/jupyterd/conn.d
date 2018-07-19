/// ConnectionInfo stores the contents of the kernel connection file created by Jupyter.
module jupyterd.conn;

import asdf.serialization : serializationKeys;

struct ConnectionInfo
{
    @serializationKeys("signature_scheme")
    string signatureScheme;
    
    @serializationKeys("transport")
    string transport;
    
    @serializationKeys("stdin_port")
    ushort stdinPort;
    
    @serializationKeys("control_port")
    ushort controlPort;
    
    @serializationKeys("iopub_port")
    ushort ioPubPort;
    
    @serializationKeys("hb_port")
    ushort hbPort;
    
    @serializationKeys("shell_port")
    ushort shellPort;
    
    @serializationKeys("key")
    string key;
    
    @serializationKeys("ip")
    string ip;
    
    string connectionString(ushort port) const
    {
        import std.format : format;
        return format!"%s://%s:%s"(transport,ip,port);
    }
}
