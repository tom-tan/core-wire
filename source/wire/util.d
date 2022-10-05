/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.util;

import dyaml : Node;
import std.json : JSONValue;

///
string scheme(string uri) pure @safe
{
    import std.algorithm : findSplit;
    if (auto ret = uri.findSplit("://"))
    {
        return ret[0];
    }
    return "";
}

///
string path(string uri) pure @safe
{
    import std.algorithm : findSplit;
    if (auto ret = uri.findSplit("://"))
    {
        return ret[2];
    }
    return uri;
}

///
JSONValue toJSON(Node node) @safe
{
    import dyaml : NodeType;
    import std.algorithm : fold, map;
    import std.array : array;
    import std.format : format;

    switch(node.type)
    {
    case NodeType.null_: return JSONValue(null);
    case NodeType.boolean: return JSONValue(node.as!bool);
    case NodeType.integer: return JSONValue(node.as!long);
    case NodeType.decimal: return JSONValue(node.as!real);
    case NodeType.string: return JSONValue(node.as!string);
    case NodeType.mapping:
        return node.mapping.fold!((acc, e) {
            acc[e.key.as!string] = e.value.toJSON;
            return acc;
        })(JSONValue((JSONValue[string]).init));
    case NodeType.sequence:
        return JSONValue(node.sequence.map!(e => e.toJSON).array);
    default: assert(false, format!"Invalid node type: %s"(node.type));
    }
}
