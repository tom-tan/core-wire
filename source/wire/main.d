/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.main;

///
int wireMain(string[] args)
{
    import dyaml : Loader;
    import std;
    import wire : defaultWire;
    import wire.core.inline : InlineCommandSet;
    import wire.cwl : download, upload, DownloadConfig, FileAttributeStrategy;
    import wire.util : absoluteURI, scheme, toJSON;

    bool showVersion;

    string configFile;
    DownloadConfig con;

    InlineCommandSet[string] icss;

    auto opts = args.getopt(
        config.caseSensitive,
        "randomize", "Make ramdomized subdirectory for each File or Directory", &con.makeRandomDir,
        // "config", "Configuration file", &configFile,
        "keep-checksum", "Keep checksums in the input object", () {
            con.checksumStrategy = FileAttributeStrategy.keep;
        },
        "no-compute-checksum", "Do not compute checksums", () {
            con.checksumStrategy = FileAttributeStrategy.noCompute;
        },
        "compute-checksum", "Compute checksums", () { con.checksumStrategy = FileAttributeStrategy.compute; },
        "validate-checksum", "Compute checksums and validate with checksums in the input object", () {
            con.checksumStrategy = FileAttributeStrategy.validate;
        },
        "inline-dl-file-cmd",
        q"[Specify the command to download files for a given scheme (example: `https:"curl -f <src-uri> -o <dst-path>"`)]",
        (string opt, string val) {
            auto splitted = enforce(val.findSplit(":"), format!"The format of `%s` must be `scheme:cmd`"(opt));
            auto scheme = splitted[0];
            auto cmd = splitted[2];
            icss.update(
                scheme,
                () => InlineCommandSet(cmd, "", ""),
                (ref InlineCommandSet ics) {
                    enforce(
                        ics.dlFileCmd.empty,
                        format!"Duplicated downloading file commands: `%s` and `%s`"(ics.dlFileCmd, cmd),
                    );
                    ics.dlFileCmd = cmd;
                },
            );
        },
        "inline-dl-dir-cmd",
        q"[Specify the command to download directories for a given schme (example: `ssh:"scp -r <src-uri> <dst-path>"`)]",
        (string opt, string val) {
            auto splitted = enforce(val.findSplit(":"), format!"The format of `%s` must be `scheme:cmd`"(opt));
            auto scheme = splitted[0];
            auto cmd = splitted[2];
            icss.update(
                scheme,
                () => InlineCommandSet("", cmd, ""),
                (ref InlineCommandSet ics) {
                    enforce(
                        ics.dlDirCmd.empty,
                        format!"Duplicated downloading file commands: `%s` and `%s`"(ics.dlDirCmd, cmd),
                    );
                    ics.dlDirCmd = cmd;
                },
            );
        },
        "inline-ul-dir-cmd",
        q"[Specify the command to upload directories for a given schme (example: `ssh:"scp -r <src-uri> <dst-path>"`)]",
        (string opt, string val) {
            auto splitted = enforce(val.findSplit(":"), format!"The format of `%s` must be `scheme:cmd`"(opt));
            auto scheme = splitted[0];
            auto cmd = splitted[2];
            icss.update(
                scheme,
                () => InlineCommandSet("", "", cmd),
                (ref InlineCommandSet ics) {
                    enforce(
                        ics.ulDirCmd.empty,
                        format!"Duplicated downloading file commands: `%s` and `%s`"(ics.ulDirCmd, cmd),
                    );
                    ics.ulDirCmd = cmd;
                },
            );
        },
        "listing", "Specify the strategy for the `listing` field (default: `no`, possible values: `no`, `shallow`, and `deep`)",
        (string opt, string val) {
            import std : to;
            import wire.cwl : LoadListing;
            con.loadListing = val.to!LoadListing;
        },
        "version", "Show version information", &showVersion,
        // "custom-core-wire-cmd", "", () {},
    );

    if (showVersion)
    {
        write(import("version"));
        return 0;
    }
    else if (opts.helpWanted || args.length != 3)
    {
        immutable baseMessage = format!(q"EOS
            core-wire: A tool/library to make CWL engines connected to remote resources
            Usage: %s [options] src.yaml dest-uri
EOS".outdent[0 .. $ - 1])(args[0].baseName);

        defaultGetoptFormatter(
            stdout.lockingTextWriter, baseMessage,
            opts.options, "%-*s %-*s%*s%s\x0a",
        );
        return 0;
    }

    // set up inlined core wires
    foreach(sch, ics; icss)
    {
        import wire.core.inline : InlineCoreWire;

        defaultWire.addCoreWire(sch, new InlineCoreWire(sch, ics), ics.type);
    }

    auto inpURI = args[1].absoluteURI;
    auto destURI = args[2].absoluteURI;

    string inpPath;
    if (inpURI.scheme == "file")
    {
        import wire.util : path;

        enforce(inpURI.path.exists && inpURI.path.isFile);
        inpPath = inpURI.path;
    }
    else
    {
        inpPath = buildPath(tempDir, randomUUID.toString);
        defaultWire.downloadFile(inpURI, "file://"~inpPath);
    }

    auto loader = Loader.fromFile(inpPath);
    loader.name = inpURI;
    auto node = loader.load;

    auto staged = destURI.scheme == "file"
        ? download(node, destURI, defaultWire, con)
        : upload(node, destURI, defaultWire);

    writeln(staged.toJSON);
    return 0;
}
