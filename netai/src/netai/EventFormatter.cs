using System.Reflection;

namespace NetAi;

static class EventFormatter
{
    public static string Format(EventInfo evt)
    {
        return $"{TypeFormatter.FormatFriendly(evt.DeclaringType!)}.{evt.Name} : {TypeFormatter.FormatFriendly(evt.EventHandlerType!)}";
    }
}
