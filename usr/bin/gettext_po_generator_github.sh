#!/usr/bin/env bash

# Capture the original language or set 'en' as default
OriginalLang=${OriginalLang:-'en'}

DIR="$1"
DIRNAME="$1"
LANGUAGES="bg cs da de el en es et fi fr he hr hu is it ja ko nl no pl pt ro ru sk sv tr uk zh"
# LANGUAGES="pt de es fr"

# Check for the existence of the OpenAI key
if [ -z "$OPENAI_KEY" ]; then
    red='\e[31;1m'
    neg='\e[37;1m'
    std='\e[m'
    echo -e "${red}Update the translation workflow.\nThe example can be found at \"https://github.com/biglinux/biglinux-package-with-translate/blob/main/.github/workflows/translate-and-build-package.yml\" ${std}"
    echo
    echo -e "${red}Update the translation workflow.\nThe example can be found at \"https://github.com/biglinux/biglinux-package-with-translate/blob/main/.github/workflows/translate-and-build-package.yml\" ${std}"
    echo -e "${red}Update the translation workflow.\nThe example can be found at \"https://github.com/biglinux/biglinux-package-with-translate/blob/main/.github/workflows/translate-and-build-package.yml\" ${std}"
    echo
    echo -e "${red}Update the translation workflow.\nThe example can be found at \"https://github.com/biglinux/biglinux-package-with-translate/blob/main/.github/workflows/translate-and-build-package.yml\" ${std}"
    sleep infinity
fi

# Detect if folder use subfolder
[ -d "$DIR/$DIR" ] && DIR="$DIR/$DIR"

# Folder locale
[ ! -d "$DIR/locale" ] && mkdir -p "$DIR/locale"

# Remove old pot
[ -e "$DIR/locale/$DIRNAME.pot" ] && rm "$DIR/locale/$DIRNAME.pot"
echo -e "Directory:\t$DIR"

#######################
# Translate shellscript
#######################
for f in $(find "$DIR" \( -path "*/.git" -o -path "*/.github" \) -prune -o -type f); do
    # Search shell script
    [ "$(file -b --mime-type "$f")" != "text/x-shellscript" ] && continue
    [ "$(grep 'git' <<< "$f")" ] && continue

    # Create .pot file
    echo -e "File:\t\t$f"
    bash --dump-po-strings "$f" >> "$DIR/locale/$DIRNAME-tmp.pot" || {
        echo "Error processing file $f"
        exit 1
    }
done

# Fix pot file
xgettext --package-name="$DIRNAME" --no-location -L PO -o "$DIR/locale/$DIRNAME.pot" -i "$DIR/locale/$DIRNAME-tmp.pot"
rm "$DIR/locale/$DIRNAME-tmp.pot"

# Check if stonejs-tools is already installed
if ! command -v stonejs &> /dev/null; then
    echo "Installing stonejs-tools..."
    sudo npm install -g stonejs-tools || {
        echo "Error installing stonejs-tools. Check your permissions."
        exit 1
    }
else
    echo "stonejs-tools is already installed."
fi

# Ensure extract.js file exists and is up-to-date
sudo wget -q https://raw.githubusercontent.com/biglinux/stonejs-tools/master/src/extract.js -O /usr/local/lib/node_modules/stonejs-tools/src/extract.js || {
    echo "Error downloading extract.js file"
    exit 1
}

# Search HTML and JS
HTML_JS_FILES=$(find "$DIR" -type f \( -iname "*.html" -o -iname "*.js" \))

if [ -n "$HTML_JS_FILES" ]; then
    ADD_JSON="json" # Enable to create .json translations for use on html/js
    stonejs extract $HTML_JS_FILES "$DIR/locale/$DIRNAME-tmp.pot" || {
        echo "Error executing stonejs extract"
    }

    if [ -f "$DIR/locale/$DIRNAME-tmp.pot" ]; then
        xgettext --package-name="$DIRNAME" --no-location -L PO -o "$DIR/locale/$DIRNAME-js.pot" -i "$DIR/locale/$DIRNAME-tmp.pot"
        rm "$DIR/locale/$DIRNAME-tmp.pot"

        # Combine files from bash and js/html
        if [[ -e "$DIR/locale/$DIRNAME-js.pot" ]]; then
            if [[ -e "$DIR/locale/$DIRNAME.pot" ]]; then
                mv "$DIR/locale/$DIRNAME.pot" "$DIR/locale/$DIRNAME-bash.pot"
                msgcat --no-wrap --strict "$DIR/locale/$DIRNAME-bash.pot" -i "$DIR/locale/$DIRNAME-js.pot" > "$DIR/locale/$DIRNAME-tmp.pot"
                xgettext --package-name="$DIRNAME" --no-location -L PO -o "$DIR/locale/$DIRNAME.pot" -i "$DIR/locale/$DIRNAME-tmp.pot"
                rm "$DIR/locale/$DIRNAME-bash.pot"
                rm "$DIR/locale/$DIRNAME-js.pot"
                [ -f "$DIR/locale/$DIRNAME-tmp.pot" ] && rm "$DIR/locale/$DIRNAME-tmp.pot"
            else
                mv "$DIR/locale/$DIRNAME-js.pot" "$DIR/locale/$DIRNAME.pot"
            fi
        fi
    fi
fi

###############
# Translate QML
###############
QML_FILES=$(find "$DIR" -type f \( -iname "*.qml" \))

if [ -n "$QML_FILES" ]; then
    echo "$QML_FILES" | while read -r file; do
        # Get relative path
        rel_path=$(realpath --relative-to="$DIR" "$file")
        echo "Processing: $rel_path"

        # Extract strings from i18n, i18nc, and qsTr
        awk -v file="$rel_path" '
        BEGIN {
            in_string = 0
            multiline_string = ""
            start_line = 0
        }
        
        function process_string(str, line_no) {
            gsub(/^["'\''"]|["'\''"]$/, "", str)  # Remove outer quotes
            gsub(/\\["'\'']/, "\"", str)          # Escape quotes for PO file
            
            if (str != "") {
                print "#: " file ":" line_no
                
                # Split into lines and format each line
                n = split(str, lines, /\n/)
                if (n == 1) {
                    print "msgid \"" str "\""
                } else {
                    print "msgid \"" lines[1] "\\n\""
                    for (i = 2; i <= n; i++) {
                        if (i == n) {
                            print "\"" lines[i] "\""
                        } else {
                            print "\"" lines[i] "\\n\""
                        }
                    }
                }
                print "msgstr \"\"\n"
            }
        }
        
        {
            line = $0
            line_number = NR
            
            if (!in_string) {
                # Look for start of i18nc
                if (match(line, /i18nc[ ]*\([^,]*,[ ]*["'\'']/, arr)) {
                    in_string = 1
                    start_line = NR
                    start_pos = RSTART + RLENGTH - 1
                    multiline_string = substr(line, start_pos + 1)
                }
                # Look for start of i18n/qsTr
                else if (match(line, /(i18n|qsTr)[ ]*\(["'\'']/, arr)) {
                    in_string = 1
                    start_line = NR
                    start_pos = RSTART + RLENGTH - 1
                    multiline_string = substr(line, start_pos + 1)
                }
            } else {
                multiline_string = multiline_string "\n" line
            }
            
            if (in_string) {
                # Look for the closing of the string
                if (match(multiline_string, /([^\\]|^)["'\'']/, arr)) {
                    in_string = 0
                    end_pos = RSTART + RLENGTH - 1
                    complete_string = substr(multiline_string, 1, end_pos - 1)
                    process_string(complete_string, start_line)
                    multiline_string = ""
                }
            }
        }' "$file" >> "$DIR/locale/$DIRNAME-tmp.pot"
    done

    # Method 3 Fix pot file
    if [ -f "$DIR/locale/$DIRNAME-tmp.pot" ]; then
        xgettext --package-name="$DIRNAME" --no-location -L PO -o "$DIR/locale/$DIRNAME-qml.pot" -i "$DIR/locale/$DIRNAME-tmp.pot"
        rm "$DIR/locale/$DIRNAME-tmp.pot"

        # Combine files from bash and js/html
        if [[ -e "$DIR/locale/$DIRNAME-qml.pot" ]]; then
            if [[ -e "$DIR/locale/$DIRNAME.pot" ]]; then
                mv "$DIR/locale/$DIRNAME.pot" "$DIR/locale/$DIRNAME-bash.pot"
                msgcat --no-wrap --strict "$DIR/locale/$DIRNAME-bash.pot" -i "$DIR/locale/$DIRNAME-qml.pot" > "$DIR/locale/$DIRNAME-tmp.pot"
                xgettext --package-name="$DIRNAME" --no-location -L PO -o "$DIR/locale/$DIRNAME.pot" -i "$DIR/locale/$DIRNAME-tmp.pot"
                rm "$DIR/locale/$DIRNAME-bash.pot"
                rm "$DIR/locale/$DIRNAME-qml.pot"
                [ -f "$DIR/locale/$DIRNAME-tmp.pot" ] && rm "$DIR/locale/$DIRNAME-tmp.pot"
            else
                mv "$DIR/locale/$DIRNAME-qml.pot" "$DIR/locale/$DIRNAME.pot"
            fi
        fi
    fi
fi

###############
# Translate .py
###############
# Search strings to translate
for f in $(find "$DIR" -type f \( -iname "*.py" \)); do
    [ ! -e "$DIR/locale/$DIRNAME.pot" ] && touch "$DIR/locale/$DIRNAME.pot"
    # Create .pot file
    echo -e "File:\t\t$f"
    xgettext -o "$DIR/locale/python.pot" "$f"
    
    if [[ -e "$DIR/locale/python.pot" ]]; then
        msgcat --no-wrap --strict "$DIR/locale/$DIRNAME.pot" -i "$DIR/locale/python.pot" > "$DIR/locale/$DIRNAME-tmp.pot"
        xgettext --package-name="$DIRNAME" --no-location -L PO -o "$DIR/locale/$DIRNAME.pot" -i "$DIR/locale/$DIRNAME-tmp.pot"
        [ -f "$DIR/locale/$DIRNAME-tmp.pot" ] && rm "$DIR/locale/$DIRNAME-tmp.pot"
    fi
    
    [ -f "$DIR/locale/python.pot" ] && rm -f "$DIR/locale/python.pot"
done

# Check if the pot file exists and has content
if [ ! -s "$DIR/locale/$DIRNAME.pot" ]; then
    echo "Warning: File $DIR/locale/$DIRNAME.pot is empty or does not exist"
else
    # Make original lang based in .pot
    msgen "$DIR/locale/$DIRNAME.pot" > "$DIR/locale/$OriginalLang.po"

    # Remove date
    sed -i '/"POT-Creation-Date:/d;/"PO-Revision-Date:/d' $DIR/locale/*

    # Process translations for each language
    for i in $LANGUAGES; do
        if [ "$i" != "$OriginalLang" ]; then
            echo "Translating to $i..."
            attranslate --srcFile="$DIR/locale/$OriginalLang.po" --srcLng="$OriginalLang" --srcFormat=po --targetFormat=po --service=openai --serviceConfig="$OPENAI_KEY" --targetFile="$DIR/locale/$i.po" --targetLng="$i"
            
            # Remove line translated with add any year from 2020 and 2029 common error on chatgpt
            awk 'BEGIN {buf=""}
            {
            if(buf ~ /^msgid/ && buf !~ /202./ && $0 ~ /^msgstr/ && $0 ~ /202./) {
                buf="";
            } else if(buf) {
                print buf;
                buf=$0;
            } else {
                buf=$0;
            }
            }
            END {if(buf) print buf}' "$DIR/locale/$i.po" > "$DIR/locale/$i.tmp"

            file1_md5=$(md5sum "$DIR/locale/$i.po" | awk '{ print $1 }')
            file2_md5=$(md5sum "$DIR/locale/$i.tmp" | awk '{ print $1 }')

            mv -f "$DIR/locale/$i.tmp" "$DIR/locale/$i.po"

            # Verify if remove date error from chatgpt and try again
            if [[ "$file1_md5" != "$file2_md5" ]]; then
                echo "Re-translating to $i due to formatting corrections..."
                attranslate --srcFile="$DIR/locale/$OriginalLang.po" --srcLng="$OriginalLang" --srcFormat=po --targetFormat=po --service=openai --serviceConfig="$OPENAI_KEY" --targetFile="$DIR/locale/$i.po" --targetLng="$i"

                # Remove line translated with add any year from 2020 and 2029 common error on chatgpt
                awk 'BEGIN {buf=""}
                {
                if(buf ~ /^msgid/ && buf !~ /202./ && $0 ~ /^msgstr/ && $0 ~ /202./) {
                    buf="";
                } else if(buf) {
                    print buf;
                    buf=$0;
                } else {
                    buf=$0;
                }
                }
                END {if(buf) print buf}' "$DIR/locale/$i.po" > "$DIR/locale/$i.tmp"

                [ -f "$DIR/locale/$i.tmp" ] && mv -f "$DIR/locale/$i.tmp" "$DIR/locale/$i.po"
            fi
        fi

        # Ensure charset is utf-8
        sed -i '/Content-Type: text\/plain;/s/charset=.*\\/charset=utf-8\\/' "$DIR/locale/$i.po"

        # Make .mo
        LANGUAGE_UNDERLINE="$(echo $i | sed 's|-|_|g')"
        mkdir -p "$DIR/usr/share/locale/$LANGUAGE_UNDERLINE/LC_MESSAGES"
        
        # Make json translations (Only if ADD_JSON is "json")
        if [[ "$ADD_JSON" == "json" ]]; then
            if [[ -e "$DIR/locale/$i.po" ]]; then
                stonejs build --format=json --merge "$DIR/locale/$i.po" "$DIR/locale/$i.json"
                sed -i "s|^{\"$i\"|{\"$DIR\"|g;s|^{\"C\"|{\"$i\"|g" "$DIR/locale/$i.json"
                
                # Copy json file to destination directory
                if [ -f "$DIR/locale/$i.json" ]; then
                    cp "$DIR/locale/$i.json" "$DIR/usr/share/locale/$LANGUAGE_UNDERLINE/LC_MESSAGES/$DIRNAME.json"
                fi
            else
                [ -f "$DIR/locale/$i.json" ] && rm -f "$DIR/locale/$i.json"
            fi
        fi

        # Generate .mo translation file
        if [ -f "$DIR/locale/$i.po" ]; then
            msgfmt "$DIR/locale/$i.po" -o "$DIR/usr/share/locale/$LANGUAGE_UNDERLINE/LC_MESSAGES/$DIRNAME.mo" || echo "Warning: Error creating .mo file for $i"
            echo "/usr/share/locale/$LANGUAGE_UNDERLINE/LC_MESSAGES/$DIRNAME.mo"
        fi
    done
fi

echo "Translation process completed successfully!"