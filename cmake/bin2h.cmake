# Copyright 2020 Sivachandran Paramasivam
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

include(CMakeParseArguments)

# Function to wrap a given string into multiple lines at the given column position.
# Parameters:
#   VARIABLE    - The name of the CMake variable holding the string.
#   AT_COLUMN   - The column position at which string will be wrapped.
function(WRAP_STRING)
    set(oneValueArgs VARIABLE AT_COLUMN)
    cmake_parse_arguments(WRAP_STRING "${options}" "${oneValueArgs}" "" ${ARGN})

    string(LENGTH ${${WRAP_STRING_VARIABLE}} stringLength)
    math(EXPR offset "0")

    while(stringLength GREATER 0)

        if(stringLength GREATER ${WRAP_STRING_AT_COLUMN})
            math(EXPR length "${WRAP_STRING_AT_COLUMN}")
        else()
            math(EXPR length "${stringLength}")
        endif()

        string(SUBSTRING ${${WRAP_STRING_VARIABLE}} ${offset} ${length} line)
        set(lines "${lines}\n${line}")

        math(EXPR stringLength "${stringLength} - ${length}")
        math(EXPR offset "${offset} + ${length}")
    endwhile()

    set(${WRAP_STRING_VARIABLE} "${lines}" PARENT_SCOPE)
endfunction()

# Function to embed contents of a file as byte array in C/C++ header file(.h). The header file
# will contain a byte array and integer variable holding the size of the array.
# Parameters
#   SOURCE_FILE     - The path of source file whose contents will be embedded in the header file.
#   VARIABLE_NAME   - The name of the variable for the byte array. The string "_SIZE" will be append
#                     to this name and will be used a variable name for size variable.
#   HEADER_FILE     - The path of header file.
#   APPEND          - If specified appends to the header file instead of overwriting it
#   NULL_TERMINATE  - If specified a null byte(zero) will be append to the byte array. This will be
#                     useful if the source file is a text file and we want to use the file contents
#                     as string. But the size variable holds size of the byte array without this
#                     null byte.
# Usage:
#   bin2h(SOURCE_FILE "Logo.png" HEADER_FILE "Logo.h" VARIABLE_NAME "LOGO_PNG")
function(BIN2H)
    set(options APPEND NULL_TERMINATE)
    set(oneValueArgs SOURCE_FILE VARIABLE_NAME HEADER_FILE)
    cmake_parse_arguments(BIN2H "${options}" "${oneValueArgs}" "" ${ARGN})

    # try to minify the source
    set(minified_file "${BIN2H_HEADER_FILE}.min.tmp")
    execute_process(COMMAND minify ${BIN2H_SOURCE_FILE} -o ${minified_file} RESULT_VARIABLE res)
    if (NOT res EQUAL 0)
        message("Failed to minify ${BIN2H_SOURCE_FILE}")
        file(COPY_FILE ${BIN2H_SOURCE_FILE} ${minified_file})
    endif()

    # reads source file contents as hex string
    file(READ ${minified_file} hexString HEX)
    string(LENGTH ${hexString} hexStringLength)

    # appends null byte if asked
    if(BIN2H_NULL_TERMINATE)
        set(hexString "${hexString}00")
    endif()

    # wraps the hex string into multiple lines at column 32(i.e. 16 bytes per line)
    wrap_string(VARIABLE hexString AT_COLUMN 32)
    math(EXPR arraySize "${hexStringLength} / 2")

    # adds '0x' prefix and comma suffix before and after every byte respectively
    string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1, " arrayValues ${hexString})
    # removes trailing comma
    string(REGEX REPLACE ", $" "" arrayValues ${arrayValues})

    # converts the variable name into proper C identifier
    string(MAKE_C_IDENTIFIER "${BIN2H_VARIABLE_NAME}" BIN2H_VARIABLE_NAME)
    string(TOUPPER "${BIN2H_VARIABLE_NAME}" BIN2H_VARIABLE_NAME)

    # declares byte array and the length variables
    set(arrayDefinition "constexpr char ${BIN2H_VARIABLE_NAME}_ARRAY[]{ ${arrayValues} };")

    if(BIN2H_APPEND)
        file(APPEND ${BIN2H_HEADER_FILE} "${arrayDefinition}\nconstexpr std::string_view ${BIN2H_VARIABLE_NAME}{${BIN2H_VARIABLE_NAME}_ARRAY, ${arraySize}};\n")
    else()
        file(WRITE ${BIN2H_HEADER_FILE} "#include <string_view>\n${arrayDefinition}\nconstexpr std::string_view ${BIN2H_VARIABLE_NAME}{${BIN2H_VARIABLE_NAME}_ARRAY, ${arraySize}};\n")
    endif()
endfunction()

# things that are assumed to be input:
# HEADER_FILE
# SOURCES
function(convert_files)
    set(oneValueArgs HEADER_FILE)
    set(multiValueArgs SOURCES)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    message("Creating c++ header file ${ARG_HEADER_FILE}")
    message("From ${ARG_SOURCES}")
    foreach(file ${ARG_SOURCES})
        get_filename_component(filename ${file} NAME)
        if (fileCreated)
            bin2h(SOURCE_FILE "${file}" HEADER_FILE "${ARG_HEADER_FILE}" VARIABLE_NAME "${filename}" APPEND)
        else()
            bin2h(SOURCE_FILE "${file}" HEADER_FILE "${ARG_HEADER_FILE}" VARIABLE_NAME "${filename}")
        endif()
        set(fileCreated TRUE)
    endforeach()
endfunction()

string(REPLACE " " ";" SOURCES ${SOURCES})
convert_files(HEADER_FILE ${HEADER_FILE} SOURCES ${SOURCES})

