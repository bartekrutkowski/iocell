# Contribution guidelines

Following the contribution guidelines saves everyone time, requires less back
and forth during the review process, and helps to ensures a consistent codebase.
*Note: historical code doesn't follow all of these guidelines*

####A few general rules first:
- Open any pull request against the `develop` branch
- Use double quotes for everything that isn't a `FOR` loop.
- Keep code to 80 characters or less, otherwise split them with a `\`. Only indent 4 spaces the first time you split the line:
```
long command \
    next line \
    next line \
```
- Comment your code
- Do not use tabs, use spaces instead. 4 spaces to start, and 4 more for each additional nesting that occurs:
```
if [ "$(command | test)" ] ; then
    if [ "$(new command | different test)" ] ; then
        for _var in ${_var_list} ; do
            stuff
        done

        if [ "$(last command | last test)" ] ; then
            echo "Note same indentation as the previous for loop as this is " \
                "not another nested level"
        fi
    fi
fi
```
- Edit `lib/ioc-help`, not generated `iocell.8`/`iocell.8.txt`, when changing
  the command reference. On the prepared FreeBSD test host, install `txt2man`
  and regenerate both files from the checkout:
```
sh ./iocell help > iocell.8.txt
txt2man -d "$(date '+%Y-%m-%d')" -t iocell -s 8 \
    -v "FreeBSD System Manager's Manual" iocell.8.txt > iocell.8
mandoc -Tlint -Wwarning iocell.8
```
  The explicit ISO date avoids a default `txt2man` date that `mandoc` cannot
  parse. Commit generated artifacts together with their help source; do not
  hand-edit the generated roff.
- Pull request description should clearly show what the change is including output if relevant.
- Squash commits before opening a pull request.
- Test and then test again! Make sure it works with the latest changes in `develop`.
- Use a line break between any statements/loops.
<br>

####IF statements
-----
- Use `-a` for AND operators and `-o` for OR operators.
Use brackets and ensure that they follow this style:
```
if [ "${VAR}" = "string" ] ; then
    stuff
fi
```
<br>

####FOR loops
-----
Make sure they follow this style:
```
for _var in ${_var_list} ; do
    stuff
done
```

<br>

####WHILE loops
-----
Make sure they follow this style:
```
while [ "${?}" -gt 0 ] ; do
    stuff
done
```

<br>

####CASE statements
----
Make sure they follow this style:
```
case "${_var}" in
    string) stuff
        ;;
    another) more stuff
        ;;
esac
```

<br>

####Variables and functions
-----
- Format functions as `__function_name ()`
- Format local variables as `_var` and global variables as `var`
- Use local variables for each function, avoid using global ones.
- Use braces on all variables "${_var}"
- Make sure you declare all variables at the top: `local _var1 _var2`
- Use a line break between declaration and actual assignment:
```
local _var1 _var2

_var1="foo"
_var2="bar"
```

<br>

####Documentation for Read The Docs
-----
The Sphinx source is `doc/source`. Update working examples and known limitations
alongside the command reference; do not present historical recipes as verified
current interfaces. Keep the runtime banner and documentation version aligned
with the project release.

Install Sphinx in a separate Python environment and validate every page and
internal reference before committing:
```
sphinx-build -E -a -n -W --keep-going -b html doc/source /tmp/iocell-doc-html
```
Build output should stay outside the source tree. See [tests/README.md](tests/README.md)
for portable and opt-in native regression commands. Website publication depends
on the documentation service's configuration; local validation is required even
when an upstream hosting service builds automatically.
