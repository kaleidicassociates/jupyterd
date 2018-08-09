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
        return InterpreterResult(InterpreterResult.State.success,cast(string)code,"");
        //return intp.interpret(code);
    }
    
    override ref const(LanguageInfo) languageInfo()
    {
        return li;
    }
}

final class DInterpreter : Interpreter
{
    LanguageInfo li = LanguageInfo("D","2.081.1",".d", "text/plain");
    
    private import drepl.engines;
    
    typeof(interpreter(dmdEngine())) intp;
    InterpreterResult last;
    
    this()
    {
        intp = interpreter(dmdEngine());
    }
    override InterpreterResult interpret(const(char)[] code)
    {
        return InterpreterResult(InterpreterResult.State.success,cast(string)code,"");
    }
    
    override ref const(LanguageInfo) languageInfo()
    {
        return li;
    }
}

