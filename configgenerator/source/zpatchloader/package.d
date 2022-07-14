import config;
import zconfig : writeExampleConfigFile;

int main()
{
    import std.file : FileException;

    try
    {
        writeExampleConfigFile!Config("zpatchloader.example.conf");
    }
    catch (FileException e)
    {
        import std.stdio : stderr;

        stderr.writeln(e.msg);
        return e.errno;
    }
    return 0;
}

