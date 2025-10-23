using System.Reflection;
using System.Text;

namespace NetAi;

static class ParameterFormatter
{
    public static string Format(ParameterInfo parameter)
    {
        var builder = new StringBuilder();
        if (parameter.IsOut) builder.Append("out ");
        else if (parameter.ParameterType.IsByRef) builder.Append("ref ");
        var type = parameter.ParameterType.IsByRef ? parameter.ParameterType.GetElementType() ?? parameter.ParameterType : parameter.ParameterType;
        builder.Append(TypeFormatter.FormatFriendly(type));
        builder.Append(" ");
        builder.Append(parameter.Name);
        if (parameter.HasDefaultValue)
        {
            builder.Append(" = ");
            builder.Append(parameter.DefaultValue ?? "null");
        }
        return builder.ToString();
    }
}
