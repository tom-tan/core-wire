/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.cwl;

import dyaml;

import std : exists, isDir, make, redBlackTree, RedBlackTree;

import wire : Wire;
import wire.core : CoreWireConfig;
import wire.util;

///
enum LeaveTmpdir
{
    always,
    onErrors,
    never,
}

/// Strategy to compute file attributes such as file sizes and checksums
enum FileAttributeStrategy
{
    keep,      /// keep input attributes
    noCompute, /// do not compute attributes
    compute,   /// compute attributes and overwite input object fields
    validate,  /// compute attributes and validate with input fields
}

/**
 * See_Also: https://www.commonwl.org/v1.2/CommandLineTool.html#LoadListingEnum
 */
enum LoadListing
{
    no,
    shallow,
    deep,
}

struct DownloadConfig
{
    ///
    LeaveTmpdir leaveTmpDir = LeaveTmpdir.onErrors;
    /// whether allowing different Files with the same basename
    bool allowDuplication;
    /// make random directory for each parameter or not
    bool makeRandomDir;

    ///
    FileAttributeStrategy checksumStrategy;

    ///
    FileAttributeStrategy sizeStrategy = FileAttributeStrategy.compute;

    ///
    LoadListing loadListing;

    /// 
    CoreWireConfig[string] config; // option to overwrite given options (is it needed?)
}

///
Node download(Node input, string destURI, Wire wire, DownloadConfig con) @safe
in(destURI.scheme == "file")
in(input.type == NodeType.mapping)
{
    import std : buildPath, mkdir, randomUUID, rmdirRecurse, tempDir;

    auto tempDestPath = buildPath(tempDir, randomUUID.toString);
    mkdir(tempDestPath);
    scope(success)
    {
        if (tempDestPath.exists && con.leaveTmpDir == LeaveTmpdir.never)
        {
            rmdirRecurse(tempDestPath);
        }
    }
    scope(failure)
    {
        if (tempDestPath.exists && con.leaveTmpDir != LeaveTmpdir.always)
        {
            rmdirRecurse(tempDestPath);
        }
    }

    auto downloaded = make!(RedBlackTree!string);
    auto ret = downloadImpl(input, tempDestPath.absoluteURI, wire, con, downloaded);

    auto destPath = destURI.path;

    if (destPath.exists)
    {
        // See_Also: https://github.com/dlang/phobos/blob/67d4521c2c53b4e8c4a5213860c49caf9396bde2/std/file.d#L4468
        () @trusted {
            import std : baseName, dirEntries, rename, SpanMode;
            foreach(string name; dirEntries(tempDestPath, SpanMode.shallow))
            {
                assert(buildPath(destPath, name.baseName).exists);
                rename(name, buildPath(destPath, name.baseName));
            }
        }();
    }
    else if (!downloaded.empty)
    {
        import std : rename, execute;
        //rename(tempDestPath, destPath);
        execute(["mv", tempDestPath, destPath]);
    }
    return ret; 
}

///
Node downloadImpl(Node input, string destURI, Wire wire, DownloadConfig con, RedBlackTree!string downloaded = make!(RedBlackTree!string)) @safe
in(destURI.scheme == "file")
in(destURI.path.exists)
in(destURI.path.isDir)
in(input.type == NodeType.mapping)
{
    import std : buildPath, mkdir, randomUUID;

    Node ret;
    foreach(string k, Node v; input)
    {
        import std : canFind;

        Node val;
        if (k.canFind(":"))
        {
            // leave extension fields as is
            val = v;
        }
        else
        {
            switch(v.type)
            {
            case NodeType.null_:
                val = Node(YAMLNull());
                break;
            case NodeType.boolean, NodeType.integer, NodeType.decimal, NodeType.string:
                val = v;
                break;
            case NodeType.sequence:
                import std : array, map;
                val = Node(
                    v.sequence.map!(i => downloadImpl(i, destURI, wire, con, downloaded)).array
                );
                break;
            case NodeType.mapping:
                if ("class" in v)
                {
                    string newDestURI;
                    if (con.makeRandomDir)
                    {
                        newDestURI = buildPath(destURI.path, randomUUID.toString);
                        mkdir(newDestURI.path);
                    }
                    else
                    {
                        newDestURI = destURI;
                    }
                    val = downloadClass(v, newDestURI, wire, con, downloaded);
                }
                else
                {
                    val = downloadImpl(v, destURI, wire, con, downloaded);
                }
                break;
            default:
                import std : format;
                import wire.exception : InvalidInput;
                throw new InvalidInput(format!"Unsupported node type: `%s`"(v.type));
            }
        }

        if (val.type != NodeType.null_)
        {
            ret.add(k, val);
        }
    }
    return ret;
}

///
Node downloadClass(Node input, string destURI, Wire wire, DownloadConfig con, RedBlackTree!string downloaded = make!(RedBlackTree!string)) @safe
in(destURI.scheme == "file")
in(destURI.path.exists)
in(destURI.path.isDir)
in(input.type == NodeType.mapping)
in("class" in input)
{
    switch(input["class"].as!string)
    {
    case "File":
        return downloadFile(input, destURI, wire, con, downloaded);
    case "Directory":
        return downloadDirectory(input, destURI, wire, con, downloaded);
    default:
        import std : format;
        import wire.exception : InvalidInput;
        throw new InvalidInput(format!"Unknown class: `%s`"(input["class"].as!string));
    }
}

///
auto downloadFile(Node file, string destDirURI, Wire wire, DownloadConfig config, RedBlackTree!string downloaded) @safe
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File")
in(destDirURI.scheme == "file")
in(destDirURI.path.exists)
in(destDirURI.path.isDir)
{
    import std : absolutePath, baseName, buildPath, dirName, extension, getSize, stripExtension;
    auto cFile = file.toCanonicalFile;
    string loc;

    if (auto con = "contents" in cFile)
    {
        import std.file : write;

        // file literal
        string bname;
        if (auto bn_ = "basename" in cFile)
        {
            bname = bn_.as!string;
        }
        else
        {
            import std : randomUUID;
            bname = randomUUID.toString;
        }
        auto destPath = buildPath(destDirURI.path, bname);
        destPath.write(con.as!string);
        loc = "file://"~destPath;
    }
    else
    {

        auto destURI = buildPath(destDirURI, cFile["basename"].as!string);
        wire.downloadFile(cFile["location"].as!string, destURI);
        loc = destURI;
    }

    auto ret = Node(cFile);
    ret["location"] = loc;
    ret["path"] = loc.path;
    ret["dirname"] = destDirURI.path;
    ret["basename"] = loc.path.baseName;
    ret["nameroot"] = loc.path.baseName.stripExtension;
    ret["nameext"] = loc.path.baseName.extension;
    ret["size"] = getSize(loc.path);

    downloaded.insert(loc.path);

    if (config.checksumStrategy == FileAttributeStrategy.compute ||
        config.checksumStrategy == FileAttributeStrategy.validate)
    {
        import std : enforce;

        auto checksum = calcChecksum(loc.path);
        enforce(config.checksumStrategy == FileAttributeStrategy.compute || cFile["checksum"] == checksum);
        ret["checksum"] = checksum;
    }

    if (auto sec = "secondaryFiles" in cFile)
    {
        import std : array, map;
        auto sf = sec.sequence.map!(s => downloadClass(s, destDirURI, wire, config, downloaded)).array;
        ret["secondaryFiles"] = sf;
    }
    return ret;
}

@safe unittest
{
    import std : buildPath, equal, exists, extension, format, isFile, mkdir, randomUUID,
                 readText, rmdirRecurse, stripExtension, tempDir;
    import std.file : write; // not to conflict with std.stdio.write
    import wire.core : CoreWireType;
    import wire.core.file : FileCoreWire, FileCoreWireConfig;
    import wire.util : absoluteURI, path;

    enum fileName = "deleteme";
    enum contents = "This is an example text.\n";

    auto srcDir = buildPath(tempDir, randomUUID.toString);
    mkdir(srcDir);
    scope(exit) rmdirRecurse(srcDir);

    auto srcURI = buildPath(srcDir, fileName).absoluteURI;
    srcURI.path.write(contents);

    auto srcYAML = format!q"EOS
class: File
location: %s
EOS"(srcURI);

    auto src = Loader.fromString(srcYAML).load.toCanonicalFile;

    auto dstDir = buildPath(tempDir, randomUUID.toString);
    mkdir(dstDir);
    scope(exit) rmdirRecurse(dstDir);
    auto dstDirURI = dstDir.absoluteURI;

    auto wire = new Wire;
    wire.addCoreWire("file", new FileCoreWire(new FileCoreWireConfig(false)), CoreWireType.both);

    auto downloaded = make!(RedBlackTree!string);

    auto staged = downloadFile(src, dstDirURI, wire, DownloadConfig.init, downloaded);
    auto dstURI = buildPath(dstDirURI, fileName);
    assert(staged.length == 8);
    assert(staged["class"] == "File");
    assert(staged["location"] == dstURI);
    assert(staged["path"] == dstURI.path);
    assert(staged["basename"] == fileName);
    assert(staged["dirname"] == dstDirURI.path);
    assert(staged["nameroot"] == fileName.stripExtension);
    assert(staged["nameext"] == fileName.extension);
    assert(staged["size"] == contents.length);

    assert(equal(downloaded[], [dstURI.path]));
}

///
auto downloadDirectory(Node dir, string dest, Wire wire, DownloadConfig config, RedBlackTree!string downloaded) @safe
in(dir.type == NodeType.mapping)
in("class" in dir)
in(dir["class"] == "Directory")
in(dest.scheme == "file")
in(dest.path.exists)
in(dest.path.isDir)
{
    import std : absolutePath, buildPath, dirName;

    auto cDir = dir.toCanonicalDirectory;
    auto ret = Node(cDir);

    if (auto listing = "listing" in cDir)
    {
        import std : array, map;
        import std.file : mkdir;

        // directory literal
        string bname;
        if (auto bn_ = "basename" in cDir)
        {
            bname = bn_.as!string;
        }
        else
        {
            import std : randomUUID;
            bname = randomUUID.toString;
            ret["basename"] = bname;
        }
        auto destPath = buildPath(dest.path, bname);
        mkdir(destPath);
        auto loc = "file://"~destPath;

        auto listingDir = loc;
        auto lst = listing.sequence.map!(s => downloadClass(s, listingDir, wire, config, downloaded)).array;
        ret["location"] = loc;
        ret["path"] = loc.path;
        ret["listing"] = lst;
    }
    else
    {
        auto destURI = buildPath(dest, cDir["basename"].as!string);
        wire.downloadDirectory(cDir["location"].as!string, destURI);
        auto loc = destURI;
        ret["location"] = loc;
        ret["path"] = loc.path;
    }

    downloaded.insert(ret["path"].as!string);

    return ret;
}

@safe unittest
{
    import std : buildPath, equal, exists, format, isDir, isFile, mkdir, randomUUID, readText, rmdirRecurse, tempDir;
    import std.file : write; // not to conflict with std.stdio.write
    import wire.core : CoreWireType;
    import wire.core.file : FileCoreWire, FileCoreWireConfig;
    import wire.util : absoluteURI, path;

    enum dirName = "deleteme";
    enum fileName = "deleteThisFile";
    enum contents = "This is an example text.\n";

    // building src directory
    auto srcDir = buildPath(tempDir, randomUUID.toString);
    mkdir(srcDir);
    scope(exit) rmdirRecurse(srcDir);

    auto srcURI = buildPath(srcDir, dirName).absoluteURI;
    mkdir(srcURI.path);
    buildPath(srcURI.path, fileName).write(contents);

    auto srcYAML = format!q"EOS
class: Directory
location: %s
EOS"(srcURI);

    auto src = Loader.fromString(srcYAML).load.toCanonicalDirectory;

    // generate dst base directory
    auto dstDir = buildPath(tempDir, randomUUID.toString);
    mkdir(dstDir);
    scope(exit) rmdirRecurse(dstDir);
    auto dstDirURI = dstDir.absoluteURI;

    auto wire = new Wire;
    wire.addCoreWire("file", new FileCoreWire(new FileCoreWireConfig(false)), CoreWireType.both);

    auto downloaded = make!(RedBlackTree!string);

    auto staged = downloadDirectory(src, dstDirURI, wire, DownloadConfig.init, downloaded);
    auto dstURI = buildPath(dstDirURI, dirName);
    assert(staged.length == 4);
    assert(staged["class"] == "Directory");
    assert(staged["location"] == dstURI);
    assert(staged["path"] == dstURI.path);
    assert(staged["basename"] == dirName);

    assert(equal(downloaded[], [dstURI.path]));
}

///
Node upload(Node node, string destURI, Wire wire)
{
    assert(false);
}


/**
 * It converts a File node to a canonicalized File node.
 *
 * A canonicalized File node is:
 * - A File object that consists of `class`, `location`, `basename`, and `secondaryFiles` if available, or
 * - A File literal that consists of `class`, `contents`, and `secondaryFiles` if available.
 * This function leaves `format`, `checksum`, `size` and extension fields as is.
 * Any other fields are not available.
 *
 * Returns: A canonicalized File node. 
 * Throws: Exception when `file` is not a valid File object.
 */
Node toCanonicalFile(Node file) @safe
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File", "`File` is expected but actual: "~file["class"].as!string)
{
    import std : dirName, enforce;

    auto ret = Node(file);
    auto path_ = "path" in file;
    auto loc_ = "location" in file;
    auto pwd = file.startMark.name.dirName;
    if (path_ is null && loc_ is null)
    {
        // file literal
        auto con = enforce("contents" in file);
        enforce(con.type == NodeType.string);
        // TODO: If `contents`` is set as a result of an Javascript expression, an `entry` in `InitialWorkDirRequirement`,
        // or read in from `cwl.output.json`, there is no specified upper limit on the size of `contents`.
        enforce(con.as!string.length <= 64*2^^10);
    }
    else if (loc_ !is null)
    {
        ret["location"] = loc_.as!string.absoluteURI(pwd);
        ret.removeAt("contents"); // TODO
    }
    else if (path_ !is null)
    {
        ret["location"] = path_.as!string.absoluteURI(pwd);
        ret.removeAt("contents"); // TODO
    }

    if (auto bname = "basename" in ret)
    {
        import std : canFind;

        enforce(!bname.as!string.canFind("/"));
    }
    else if (auto p_ = "location" in ret)
    {
        if (auto l_ = "location" in ret)
        {
            import std : baseName;
            ret["basename"] = l_.as!string.path.baseName;
        }
    }

    ret.removeAt("path");
    ret.removeAt("dirname");
    ret.removeAt("nameroot");
    ret.removeAt("nameext");

    if (auto sec = "secondaryFiles" in file)
    {
        import std : array, empty, map;

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

        if (canonicalizedSec.empty)
        {
            ret.removeAt("secondaryFiles");
        }
        else
        {
            ret["secondaryFiles"] = canonicalizedSec;
        }
    }

    return ret;
}

///
@safe unittest
{
    enum origYAML = q"EOS
        class: File
        path: /foo/bar/buzz.txt
        ext:field: "This is an extension field."
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalFile;
    assert(origFile.length == 4);
    assert(origFile["class"] == "File");
    assert(origFile["location"] == "file:///foo/bar/buzz.txt");
    assert(origFile["basename"] == "buzz.txt");
    assert(origFile["ext:field"] == "This is an extension field.");
}

///
@safe unittest
{
    enum origYAML = q"EOS
        class: File
        contents: |
            foo
            bar
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalFile;
    assert(origFile.length == 2);
    assert(origFile["class"] == "File");
    assert(origFile["contents"] == "foo\nbar\n");
}

/**
 * Returns: A canonicalized Directory Node. That is,
 *   - Directory object in which `listing` and `basename` are available but `path` and `location` are not available, or
 *   - Directory object in which `location` and `basename` are available but `path` and `listing` are not available
 * Throws: Exception when `dir` is not valid Directory object.
 */
Node toCanonicalDirectory(Node dir) @safe
in(dir.type == NodeType.mapping)
in("class" in dir)
in(dir["class"] == "Directory", "`Directory` is expected but actual: "~dir["class"].as!string)
{
    import std : dirName, enforce;

    auto ret = Node(dir);
    auto path_ = "path" in dir;
    auto loc_ = "location" in dir;
    auto pwd = dir.startMark.name.dirName;

    if (path_ is null && loc_ is null)
    {
        // directory literal
        auto listing = enforce("listing" in dir);
        enforce(listing.type == NodeType.sequence);
    }
    else if (loc_ !is null)
    {
        ret["location"] = loc_.as!string.absoluteURI(pwd);
        ret.removeAt("listing");
    }
    else if (path_ !is null)
    {
        ret["location"] = path_.as!string.absoluteURI(pwd);
        ret.removeAt("listing");
    }

    if (auto bname = "basename" in dir)
    {
        import std : canFind;

        enforce(!bname.as!string.canFind("/"));
    }
    else if (auto p_ = "location" in ret)
    {
        import std : baseName;
        ret["basename"] = p_.as!string.path.baseName;
    }

    ret.removeAt("path");

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
        ret["listing"] = canonicalizedListing;
    }
    return ret;
}

///
@safe unittest
{
    import std : to;
    enum origYAML = q"EOS
        class: Directory
        path: /foo/bar/buzzDir
        ext:field: "This is an extension field."
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalDirectory;
    assert(origFile.length == 4, "Actual: "~origFile.length.to!string);
    assert(origFile["class"] == "Directory");
    assert(origFile["location"] == "file:///foo/bar/buzzDir");
    assert(origFile["basename"] == "buzzDir");
    assert(origFile["ext:field"] == "This is an extension field.");
}

///
@safe unittest
{
    enum origYAML = q"EOS
        class: Directory
        listing:
          - class: File
            contents: |
              foo
          - class: File
            contents: |
              bar
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalDirectory;
    assert(origFile.length == 2);
    assert(origFile["class"] == "Directory");
    assert(origFile["listing"].length == 2);
    assert(origFile["listing"][0].length == 2);
    assert(origFile["listing"][0]["class"] == "File");
    assert(origFile["listing"][0]["contents"] == "foo\n");
    assert(origFile["listing"][1].length == 2);
    assert(origFile["listing"][1]["class"] == "File");
    assert(origFile["listing"][1]["contents"] == "bar\n");
}
