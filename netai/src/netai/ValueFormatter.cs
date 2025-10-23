using System;
using System.Linq;

namespace NetAi;

static class ValueFormatter
{
    public static string Format(object? value)
    {
        if (value == null) return "null";
        return value switch
        {
            string s => $"\"{s}\"",
            char c => $"'{c}'",
            bool b => b ? "true" : "false",
            Enum e => $"{e.GetType().Name}.{e}",
            Array array => $"[{string.Join(", ", array.Cast<object?>().Select(Format))}]",
            _ => value.ToString() ?? string.Empty
        };
    }
}
