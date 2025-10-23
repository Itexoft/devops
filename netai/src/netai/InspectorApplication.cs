using System;
using System.IO;
using System.Linq;
using System.Reflection;

namespace NetAi;

sealed class InspectorApplication
{
    public int Run(string[] args)
    {
        if (args.Length < 2)
        {
            PrintUsage();
            return 1;
        }
        var assemblyPath = Path.GetFullPath(args[0]);
        if (!File.Exists(assemblyPath))
        {
            Console.Error.WriteLine("Assembly not found");
            return 1;
        }
        var command = args[1].Trim().ToLowerInvariant();
        var options = OptionSet.Parse(args.Skip(2));
        var baseDirectory = Path.GetDirectoryName(assemblyPath) ?? Directory.GetCurrentDirectory();
        InspectionLoadContext? context = null;
        try
        {
            context = new InspectionLoadContext(baseDirectory);
            Assembly assembly;
            try
            {
                assembly = context.LoadFromAssemblyPath(assemblyPath);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.Message);
                return 1;
            }
            var inspector = new AssemblyInspector(assembly, assemblyPath);
            var executor = new CommandExecutor(inspector);
            return executor.Execute(command, options);
        }
        finally
        {
            context?.Unload();
            GC.Collect();
            GC.WaitForPendingFinalizers();
        }
    }

    void PrintUsage()
    {
        Console.WriteLine("Usage: netai <assemblyPath> <command> [options]");
        Console.WriteLine("Commands: summary, types, type, members, method, inheritance, implements, search, attributes, resources, entrypoint, dump-json");
    }
}
