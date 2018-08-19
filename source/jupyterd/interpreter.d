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
	intp.interpret(`import std.experimental.all;`);
    }
    override InterpreterResult interpret(const(char)[] code)
    {
	    import std.string:splitLines, join;
	    import std.algorithm;
	    import std.array:array;
	    import std.range:back;
	    import std.stdio:stderr,writeln;
	    InterpreterResult.State state;
	    auto result = code.splitLines.map!(line=>intp.interpret(line)).array;
	    auto success = (result.all!(line=>line.state != InterpreterResult.State.error));
	    if (!success)
		   state = InterpreterResult.State.error;
	    else 
		    state = ((result.length==0) || (result.back.state != InterpreterResult.State.incomplete) )? InterpreterResult.State.success : InterpreterResult.State.incomplete;
	    auto errorOutput = result.map!(line=>line.stderr).join("\n");
	    auto stdOutput = result.map!(line=>line.stdout).join("\n");
	    stderr.writeln(state,stdOutput,errorOutput);
	    return InterpreterResult(state,stdOutput,errorOutput);
    }
    
    override ref const(LanguageInfo) languageInfo()
    {
        return li;
    }
}

