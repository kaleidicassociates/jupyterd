import juypterd.interpreter;
import juypterd.kernel;
import zmqd;
import std.stdio;

int main(string[] args)
{
    Interpreter i;

    switch(args[1])
    {
        case "echo":
            i = new EchoInterpreter();
            break;
        default:
            return 1;
    }
    auto k = Kernel(i,/*connection string=*/args[2]);
    k.mainloop();
    return 0;
}
