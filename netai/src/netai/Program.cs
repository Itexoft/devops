using System;

namespace NetAi;

public static class Program
{
    public static int Main(string[] args)
    {
        var app = new InspectorApplication();
        return app.Run(args);
    }
}
