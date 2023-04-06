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
    import wire.cwl : download, upload, DownloadConfig;
    import wire.util : absoluteURI, scheme, toJSON;

    string destURI;
    string configFile;
    DownloadConfig con;

    InlineCommandSet[string] icss;

    auto opts = args.getopt(
        config.caseSensitive,
        config.required,
        "dest", "Destination base URI",  (string opt, string uri) { destURI = uri.absoluteURI; },
        "randomize", "Make ramdomized subdirectory for each File or Directory", &con.makeRandomDir,
        "config", "Configuration file", &configFile,
        "inline-dl-file-cmd", q"[format: `scheme:"cmd"`]", (string opt, string val) {
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
        "inline-dl-dir-cmd", q"[format: `scheme:"cmd"`]", (string opt, string val) {
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
        "inline-ul-dir-cmd", q"[format: `scheme:"cmd"`]", (string opt, string val) {
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
        // "custom-core-wire-cmd", "", () {},
    );

    if (opts.helpWanted || args.length != 2)
    {
        immutable baseMessage = format!(q"EOS
            core-wire: A tool/library to make CWL engines connected to remote resources
            Usage: %s [options] src.yml
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

    auto inpFile = args[1].absolutePath;

    enforce(inpFile.exists && inpFile.isFile);
    auto loader = Loader.fromFile(inpFile);
    loader.name = "file://"~inpFile;

    auto node = loader.load;

    auto staged = destURI.scheme == "file"
        ? download(node, destURI, defaultWire, con)
        : upload(node, destURI, defaultWire);

    writeln(staged.toJSON);
    return 0;
}
