/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.core.inline;

import wire.core : CoreWire, CoreWireConfig, CoreWireType;

import std : empty;

struct InlineCommandSet
{
    string dlFileCmd, dlDirCmd;
    string ulDirCmd;

    CoreWireType type() const @nogc nothrow pure @safe
    {
        auto supportDl = (!dlFileCmd.empty || !dlDirCmd.empty) ? CoreWireType.down : CoreWireType.none;
        auto supportUl = !ulDirCmd.empty ? CoreWireType.up : CoreWireType.none;

        return supportDl | supportUl;
    }
}

class InlineCoreWire : CoreWire
{
    ///
    this(string scheme, InlineCommandSet ics)
    {
        import std : enforce, empty;

        this.schemes_ = [scheme];
        this.ics = ics;

        enforce(!ics.dlFileCmd.empty || !ics.dlDirCmd.empty || !ics.ulDirCmd.empty);
        if (!ics.dlFileCmd.empty)
        {
            enforceValidCommand(ics.dlFileCmd);
        }
        if (!ics.dlDirCmd.empty)
        {
            enforceValidCommand(ics.dlDirCmd);
        }
        if (!ics.ulDirCmd.empty)
        {
            enforceValidCommand(ics.ulDirCmd);
        }
    }

    ///
    override void downloadFile(string src, string dst) const
    {
        import std : enforce, executeShell, format;

        import wire.exception : ResourceError, UnsupportedFeature;
        import wire.util : path, scheme;

        auto sch = src.scheme;
        enforce!UnsupportedFeature(
            !ics.dlFileCmd.empty,
            format!"Downloading files is not supported by inlined core wire for `%s`"(sch),
        );

        auto ret = executeShell(buildCommand(ics.dlFileCmd, src, dst));
        enforce!ResourceError(
            ret.status == 0,
            format!"Downloading `%s` failed with the following message: `%s`"(src, ret.output)
        );
    }

    ///
    override void downloadDirectory(string src, string dst) const
    {
        import std : format;

        import wire.exception : ResourceError, UnsupportedFeature;
        import wire.util : path, scheme;

        import std : enforce, executeShell;

        auto sch = src.scheme;
        enforce!UnsupportedFeature(
            !ics.dlDirCmd.empty,
            format!"Downloading directories is not supported by inlined core wire for `%s`"(sch),
        );

        auto ret = executeShell(buildCommand(ics.dlDirCmd, src, dst));
        enforce!ResourceError(
            ret.status == 0,
            format!"Downloading `%s` failed with the following message: `%s`"(src, ret.output)
        );
    }

    ///
    override void uploadDirectory(string src, string dst) const
    {
        import std : format;

        import wire.exception : ResourceError, UnsupportedFeature;
        import wire.util : path, scheme;

        import std : enforce, executeShell;

        auto sch = src.scheme;
        enforce!UnsupportedFeature(
            !ics.ulDirCmd.empty,
            format!"Uploading directories is not supported by inlined core wire for `%s`"(sch),
        );

        auto ret = executeShell(buildCommand(ics.ulDirCmd, src, dst));
        enforce!ResourceError(
            ret.status == 0,
            format!"Uploading `%s` failed with the following message: `%s`"(src, ret.output)
        );
    }

    ///
    override bool supportDownloadDirectory() const @nogc nothrow pure @safe
    {
        return !ics.dlDirCmd.empty;
    }

    ///
    override CoreWireType type() const @nogc nothrow pure @safe
    {
        return ics.type;
    }

protected:
    override const(string[]) schemes() const @nogc nothrow pure @safe
    {
        return schemes_;
    }

private:
    InlineCommandSet ics;
    string[] schemes_;
}

///
auto buildCommand(string baseCommand, string src, string dst) pure
{
    import std : replace;
    import wire.util : path;

    return baseCommand
        .replace("<src-path>", src.path)
        .replace("<src-uri>", src)
        .replace("<dst-path>", dst.path)
        .replace("<dst-uri>", dst);
}

///
void enforceValidCommand(string cmd) pure
in(!cmd.empty)
{
    import std : canFind, enforce, format;
    enforce(
        cmd.canFind("<src-path>") || cmd.canFind("<src-uri>"),
        format!"<src-path> or <src-uri> must be previded in the commmand `%s`"(cmd),
    );
    enforce(
        cmd.canFind("<dst-path>") || cmd.canFind("<dst-uri>"),
        format!"<dst-path> or <dst-uri> must be previded in the commmand `%s`"(cmd),
    );
}