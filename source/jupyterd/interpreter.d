module juypterd.interpreter;
import juypterd.kernel;
struct LanguageInfo
{
    string name;
    string languageVersion;
    string fileExtension;
    string mimeType;
}

interface Interpreter
{
    Kernel.Status interpret(string code, out string result);
    
    string lastErrorName();
    
    string lastErrorValue();

    string[] backtrace();
    ref const(LanguageInfo) languageInfo();

}

final class EchoInterpreter : Interpreter
{
    LanguageInfo li = LanguageInfo("echo","1.0.0",".txt", "text/plain");
    
    override Kernel.Status interpret(string code, out string result)
    {
        result = code;
        return Kernel.Status.ok;
    }
    
    override string lastErrorName()
    {
        return "";
    }
    
    override string lastErrorValue()
    {
        return "";
    }
    
    override string[] backtrace()
    {
        return [""];
    }
    override ref const(LanguageInfo) languageInfo()
    {
        return li;
    }
}
