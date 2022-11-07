/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.core;

import std.algorithm : canFind;
import std.file : exists, isDir, isFile;
import std.path : dirName;

import wire.util : path, scheme;

///
enum CoreWireType : ubyte
{
    none = 0b00,
    up   = 0b01,
    down = 0b10,
    both = 0b11,
}

///
interface CoreWire
{
    ///
    void downloadFile(string src, string dst) const
    in(dst.scheme == "file")
    in(schemes.canFind(src.scheme))
    in(dst.path.dirName.exists && dst.path.dirName.isDir)
    out(;dst.path.exists && dst.path.isFile);

    ///
    void downloadDirectory(string src, string dst) const
    in(dst.scheme == "file")
    in(schemes.canFind(src.scheme))
    in(dst.path.dirName.exists && dst.path.dirName.isDir)
    out(;dst.path.exists && dst.path.isDir);

    ///
    void uploadFile(string src, string dst) const
    in(src.scheme == "file")
    in(schemes.canFind(dst.scheme))
    in(src.path.exists && src.path.isFile);

    ///
    final bool canSupport(string scheme) const
    {
        return schemes.canFind(scheme);
    }

    /**
     * Returns: true if this core wire can make directories to the remote resources
     */
    bool canMkdir() const;

    ///
    CoreWireType type() const;

protected:
    string[] schemes() const;
}

///
interface CoreWireConfig
{
}
