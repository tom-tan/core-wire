/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.cwl;

import dyaml;

import wire : Wire;
import wire.core : CoreWireConfig;
import wire.util;

struct DownloadConfig
{
    /// always, onError, or never
    int removeTmpdir;
    /// allow to make random directory for each parameter
    bool makeRandomDir;

    /// 
    CoreWireConfig[string] config;
}

/**
 * It makes a new sub directory for each parameter
 */
Node download(Node input, string destURI, Wire wire, DownloadConfig con)
in(destURI.scheme == "file")
in(input.type == NodeType.mapping)
{
    import std.file : dirEntries, exists, rename, mkdir, rmdirRecurse, SpanMode, tempDir;
    import std.path : baseName, buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir, randomUUID.toString);
    mkdir(dir);
    scope(exit)
    {
        rmdirRecurse(dir); // TODO: leave on error?
    }

    auto destPath = destURI.path;

    Node ret;
    foreach(string k, Node v; input)
    {
        import std : canFind;
        Node val;
        if (k.canFind(":"))
        {
            val = v;
        }
        else
        {
            auto dest = con.makeRandomDir
                ? buildPath(destPath, randomUUID.toString)
                : destPath;
            val = downloadParam(v, "file://"~dest, wire, con);
        }

        if (val.type != NodeType.null_)
        {
            ret.add(k, val);
        }
    }

    if (destPath.exists)
    {
        foreach(string name; dirEntries(dir, SpanMode.shallow))
        {
            rename(name, buildPath(destPath, name.baseName));
        }
        rmdirRecurse(dir);
    }
    else
    {
        rename(dir, destPath);
    }
    return ret;
}

///
Node upload(Node input, string destURI, Wire wire)
{
    // make tmpdir
    // download[file,copy/symlink] to tmpdir
    // copy & remove
    return input;
}

///
Node downloadParam(Node inp, string dest, Wire wire, DownloadConfig con)
{
    import std : format;
    import wire.exception : WireException;

    switch(inp.type)
    {
    case NodeType.null_:
        return Node(YAMLNull());
    case NodeType.boolean, NodeType.integer, NodeType.decimal, NodeType.string:
        return inp;
    case NodeType.sequence:
        import std : array, map;
        return Node(
            inp.sequence.map!(i => i.downloadParam(dest, wire, con)).array
        );
    case NodeType.mapping:
        if (auto class_ = "class" in inp)
        {
            auto c = class_.as!string;
            switch(c)
            {
            case "File": return inp.stagingFile(dest, wire, con);
            case "Directory": return inp.stagingDirectory(dest, wire, con);
            default:
                throw new WireException(format!"Unknown class: `%s`"(c));
            }
        }
        return download(inp, dest, wire, con);
    default:
        throw new WireException(format!"Unsupported node type: `%s`"(inp.type));
    }
}

/// TODO
auto stagingFile(Node file, string dst, Wire wire, DownloadConfig con)
{
    import std : absolutePath, buildPath, dirName;

    Node ret = Node(file);
    ret.add("location", buildPath(file.startMark.name.dirName, file["location"].as!string));
    if (auto sec = "secondaryFiles" in file)
    {
        import std : array, map;
        auto sf = sec.sequence.map!(s => downloadParam(s, dst, wire, con)).array;
        ret.add("secondaryFiles", sf);
    }
    return ret;
}

/// TODO
auto stagingDirectory(Node dir, string dst, Wire wire, DownloadConfig con)
{
    Node ret;
    ret.add("class", "Directory");
    return dir;
}
