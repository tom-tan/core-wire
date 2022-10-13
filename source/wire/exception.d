/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.exception;

///
class WireException : Exception
{
    private import std.exception : basicExceptionCtors;
    mixin basicExceptionCtors;
}

/// input file not found
/// network error