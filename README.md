# tsl
Text Substitution Language written in Fitted Software Tools Modula-2

A DSL for making multiple changes to text files with or without prompting.

Example TSL control file
```
    NOTE Example Script
    SHOW ALL
    DUPLICATES ON
    BREAKON ()+-*/\`'"~!@#$%^&=,.<>?|[]
    MESSAGE BREAKS AT ()+-*/\`'"~!@#$%^&=,.<>?|[]

    NOTE Filename taken from commandline.
    FILE $1

SUBST "end" with "dne" nocase whole confirm
subst "end;" with ";dne" nocase whole confirm
SUBST "procedure" with "erudecorp" nocase whole confirm
subst "function" with "noitcnuf" nocase whole confirm

GO
END
```

See Doucmentation.txt for a longer description.

See the [xlb](https://github.com/axtens/xlb) project for required non-FST libraries.

Building and/or converting to another Modula-2 is left as a task for the reader and/or the author should he find the time.

Other Modula-2 compilers: [M2F](http://floppsie.comp.glam.ac.uk/Glamorgan/gaius/web/m2fabout.html), [GNU Modula-2](https://www.nongnu.org/gm2/download.html), [XDS](https://github.com/excelsior-oss/xds) and [ADW](https://www.modula2.org/adwm2/).

Other good Modula-2 information can be found at [Peter Moylan](http://www.pmoylan.org/pages/m2/Modula2.html)'s site.
