module juypterd.interpreter;
import juypterd.kernel;
import drepl.interpreter : InterpreterResult, interpreter;
struct LanguageInfo
{
    string name;
    string languageVersion;
    string fileExtension;
    string mimeType;
}

interface Interpreter
{
    InterpreterResult interpret(const(char)[] code);
    
    string lastErrorName();
    
    string lastErrorValue();

    string[] backtrace();
    ref const(LanguageInfo) languageInfo();

}

final class EchoInterpreter : Interpreter
{
    LanguageInfo li = LanguageInfo("echo","1.0.0",".txt", "text/plain");
    
    private import drepl.engines;
    
    typeof(interpreter(echoEngine())) intp;
    InterpreterResult last;
    
    this()
    {
        intp = interpreter(echoEngine());
    }
    override InterpreterResult interpret(const(char)[] code)
    {
        return intp.interpret(code);
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
