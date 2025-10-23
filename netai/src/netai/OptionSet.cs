using System;
using System.Collections.Generic;

namespace NetAi;

sealed class OptionSet
{
    readonly Dictionary<string, List<string>> values = new(StringComparer.OrdinalIgnoreCase);
    readonly List<string> positional = new();

    public static OptionSet Parse(IEnumerable<string> args)
    {
        var optionSet = new OptionSet();
        string? pendingKey = null;
        foreach (var token in args)
        {
            if (string.IsNullOrWhiteSpace(token))
            {
                continue;
            }
            if (token.StartsWith("--", StringComparison.Ordinal) && token.Length > 2)
            {
                pendingKey = token[2..];
                optionSet.AddValue(pendingKey, "true", replace: false);
                continue;
            }
            if (token.StartsWith("-", StringComparison.Ordinal) && token.Length > 1)
            {
                pendingKey = token[1..];
                optionSet.AddValue(pendingKey, "true", replace: false);
                continue;
            }
            if (pendingKey != null)
            {
                optionSet.AddValue(pendingKey, token, replace: true);
                pendingKey = null;
            }
            else
            {
                optionSet.positional.Add(token);
            }
        }
        return optionSet;
    }

    void AddValue(string key, string value, bool replace)
    {
        if (!values.TryGetValue(key, out var list))
        {
            list = new List<string>();
            values[key] = list;
        }
        if (replace && list.Count > 0)
        {
            list[^1] = value;
        }
        else
        {
            list.Add(value);
        }
    }

    public bool Has(string key) => values.ContainsKey(key);

    public string? Get(string key)
    {
        if (values.TryGetValue(key, out var list) && list.Count > 0)
        {
            return list[^1];
        }
        return null;
    }

    public IEnumerable<string> GetAll(string key)
    {
        if (values.TryGetValue(key, out var list))
        {
            foreach (var item in list)
            {
                yield return item;
            }
        }
    }

    public IReadOnlyList<string> Positional => positional;
}
