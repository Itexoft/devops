using System.Collections.Generic;
using System.Reflection;
using System.Text;

namespace NetAi;

static class AttributeFormatter
{
    public static string Format(CustomAttributeData attribute)
    {
        var builder = new StringBuilder();
        builder.Append(TypeFormatter.FormatFriendly(attribute.AttributeType));
        if (attribute.ConstructorArguments.Count > 0 || attribute.NamedArguments.Count > 0)
        {
            builder.Append("(");
            var parts = new List<string>();
            foreach (var arg in attribute.ConstructorArguments)
            {
                parts.Add(ValueFormatter.Format(arg.Value));
            }
            foreach (var arg in attribute.NamedArguments)
            {
                parts.Add($"{arg.MemberName}={ValueFormatter.Format(arg.TypedValue.Value)}");
            }
            builder.Append(string.Join(", ", parts));
            builder.Append(")");
        }
        return builder.ToString();
    }
}
