/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.cwl;

import dyaml;

import std : exists;

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
        if (dir.exists)
        {
            rmdirRecurse(dir); // TODO: leave on error?
        }
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

///
auto downloadFile(Node file, string dest, Wire wire, DownloadConfig config)
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File")
in(dest.path.exists)
{
    import std : absolutePath, buildPath, dirName;

    if (auto con = "contents" in file)
    {
        import std.file : write;

        // file literal
        string bname;
        if (auto bn_ = "basename" in file)
        {
            bname = bn_.as!string;
        }
        else
        {
            import std : randomUUID;
            bname = randomUUID.toString;
        }
        auto destPath = buildPath(dest.path, bname);
        destPath.write(con.as!string);
    }
    else
    {
        //
    }

    Node ret = Node(file);
    ret.add("location", buildPath(file.startMark.name.dirName, file["location"].as!string));
    if (auto sec = "secondaryFiles" in file)
    {
        import std : array, map;
        auto sf = sec.sequence.map!(s => downloadParam(s, dest, wire, config)).array;
        ret.add("secondaryFiles", sf);
    }
    return ret;
}

/**
 * Returns: A canonicalized File Node
 * Throws: Exception when `file` is not valid File object.
 */
Node toCanonicalFile(Node file)
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File")
{
    import std : enforce;

    auto ret = Node(file);
    auto path_ = "path" in file;
    auto loc_ = "location" in file;
    auto pwd = file.startMark.name;
    if (path_ is null && loc_ is null)
    {
        // file literal
        auto con = enforce("contents" in file);
        enforce(con.type == NodeType.string);
        enforce(con.as!string.length <= 64*2^^10);
    }
    else if (loc_ !is null)
    {
        ret.add("location", loc_.as!string.absoluteURI(pwd));
        ret.remove("contents");
    }
    else if (path_ !is null)
    {
        ret.add("location", path_.as!string.absoluteURI(pwd));
        ret.remove("contents");
    }

    if (auto l = "location" in ret)
    {
        ret.add("path", l.as!string.path);
    }

    if (auto bname = "basename" in file)
    {
        import std : canFind;

        enforce(!bname.as!string.canFind("/"));
    }
    else
    {
        if (auto p_ = "path" in ret)
        {
            import std : baseName;
            ret.add("basename", p_.as!string.baseName);
        }
    }

    // TODO: how to do with `size` and `checksum`?

    if (auto sec = "secondaryFiles" in file)
    {
        import std : array, map;

        auto canonicalizedSec = sec
            .sequence
            .map!((s)
            {
                auto class_ = enforce("class" in s).as!string;
                if (class_ == "File")
                {
                    return s.toCanonicalFile;
                }
                else if (class_ == "Directory")
                {
                    return s.toCanonicalDirectory;
                }
                throw new Exception("Unknown class: "~class_);
            })
            .array;
        ret.add("secondaryFiles", canonicalizedSec);
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

/**
 * Returns: A canonicalized Directory Node
 * Throws: Exception when `dir` is not valid Directory object.
 */
Node toCanonicalDirectory(Node dir)
in(dir.type == NodeType.mapping)
in("class" in dir)
in(dir["class"] == "Directory")
{
    import std : enforce;

    auto ret = Node(dir);
    auto path_ = "path" in dir;
    auto loc_ = "location" in dir;
    auto pwd = dir.startMark.name;

    if (path_ is null && loc_ is null)
    {
        // directory literal
        auto listing = enforce("liting" in dir);
        enforce(listing.type == NodeType.sequence);
    }
    else if (loc_ !is null)
    {
        ret.add("location", loc_.as!string.absoluteURI(pwd));
        ret.remove("listing");
    }
    else if (path_ !is null)
    {
        ret.add("location", path_.as!string.absoluteURI(pwd));
        ret.remove("listing");
    }

    if (auto l = "location" in ret)
    {
        ret.add("path", l.as!string.path);
    }

    if (auto bname = "basename" in dir)
    {
        import std : canFind;

        enforce(!bname.as!string.canFind("/"));
    }
    else
    {
        if (auto p_ = "path" in ret)
        {
            import std : baseName;
            ret.add("basename", p_.as!string.baseName);
        }
    }

    // listing
    if (auto listing = "listing" in dir)
    {
        import std : array, map;

        auto canonicalizedListing = listing
            .sequence
            .map!((s)
            {
                auto class_ = enforce("class" in s).as!string;
                if (class_ == "File")
                {
                    return s.toCanonicalFile;
                }
                else if (class_ == "Directory")
                {
                    return s.toCanonicalDirectory;
                }
                throw new Exception("Unknown class: "~class_);
            })
            .array;
        ret.add("listing", canonicalizedListing);
    }

    return ret;
}