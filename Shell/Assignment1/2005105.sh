# Function for prompting user for proper cmd
prompt() {
    echo "Please use: $0 -i input_file.txt"
    exit 1
}

# Extracting proper command
while getopts ":i:" opt; do
    case ${opt} in
    i)
        input_file=$OPTARG
        ;;
    \?)
        prompt
        ;;
    esac
done

# Input file verification
if [ -z "$input_file" ] || [ ! -f "$input_file" ]; then
    prompt
fi

if [[ "$input_file" != *.txt ]]; then
    echo "Invalid file format for $input_file, must pass a .txt file"
    exit 1
fi

# Reading input file
readarray -t lines <"$input_file"

use_archive=${lines[0]}
allowed_archive_formats=${lines[1]}
allowed_languages=${lines[2]}
total_marks=${lines[3]}
unmatched_output_penalty=${lines[4]}
working_directory=${lines[5]}
student_id_range=${lines[6]}
expected_output_file_location=${lines[7]}
submission_violation_penalty=${lines[8]}
plagiarism_file=${lines[9]}
plagiarism_penalty=${lines[10]}

IFS=' ' read -r student_id_start student_id_end <<<"$student_id_range"

# For submission confirmation
number_of_students=$((student_id_end - student_id_start + 1))
bool_array=()
for ((i = 0; i < number_of_students; i++)); do
    bool_array[i]=0
done

# For sorting correct and incorrect submissions
mkdir -p issues checked
rm -rf issues/* checked/*

# CSV file initiation
echo "id,marks,marks_deducted,total_marks,remarks" >marks.csv

# Traversing submitted files
for student_file in "$working_directory"/*; do

    # Error
    if [ -z "$student_file" ]; then
        continue
    fi

    # Extracting required information
    file_name=$(basename "$student_file")
    student_id="${file_name%.*}"
    student_folder="checked/$student_id"
    remarks=""
    marks_deducted=0

    # Student id verification
    if ! [[ "$student_id" -ge "$student_id_start" && "$student_id" -le "$student_id_end" ]]; then
        continue
    fi

    # Confirming submsision, but no evaluation
    index=$((student_id - student_id_start))
    bool_array[index]=1

    # For - archived file expected
    if [ "$use_archive" == "true" ]; then

        # Unarchived, submitted as folder
        if [ -d "$student_file" ]; then
            student_file=$(find "$student_file" -type f | head -n 1)

            # file_name=$(basename "$student_file")
            # student_id="${file_name%.*}"
            # student_folder="checked/$student_id"

            mkdir -p "$student_folder"
            cp "$student_file" "$student_folder/"
            remarks="$remarks issue case #1"
        # Submitted as archived
        else
            # File extention verification
            baseVar=$(basename "$file_name")
            extension="${baseVar##*.}"

            if [[ ! " ${allowed_archive_formats} " =~ " ${extension} " ]]; then
                remarks="$remarks issue case #2"
                marks_deducted=$((marks_deducted + submission_violation_penalty))
                cp "$student_file" issues/
                echo "$student_id,0,0,$total_marks,$remarks" >>marks.csv

                continue
            fi

            # Extract file to folder
            mkdir -p "$student_folder"
            if [ "$extension" == "zip" ]; then
                unzip "$student_file" -d "$student_folder" &>/dev/null
            elif [ "$extension" == "rar" ]; then
                unrar x "$student_file" "$student_folder" &>/dev/null
            elif [ "$extension" == "tar" ]; then
                tar -xf "$student_file" -C "$student_folder" &>/dev/null
            fi
        fi

        # Verify extracted folder submission
        extracted_file_name=$(basename "$student_file")
        extracted_student_id="${extracted_file_name%.*}"

        if [[ "$extracted_student_id" != "$student_id" ]]; then
            remarks="$remarks issue case #4"
            echo $student_id $extracted_student_id
            echo "$student_id,0,0,$total_marks,$remarks" >>marks.csv
        fi

    # For - archived file not expected
    else
        # Folder submitted
        if [ -d "$student_file" ]; then
            student_file=$(find "$student_file" -type f | head -n 1)

            file_name=$(basename "$student_file")
            student_id="${file_name%.*}"
            student_folder="checked/$student_id"

            mkdir -p "$student_folder"
            cp "$student_file" "$student_folder/"
            remarks="$remarks issue case #1"
        # File submitted
        elif [ -f "$student_file" ]; then

            file_name=$(basename "$student_file")
            student_id="${file_name%.*}"
            student_folder="checked/$student_id"

            mkdir -p "$student_folder"
            cp "$file_name" "$student_folder/"
        fi
    fi

    # Extracting submission file from folder
    submission_file=$(find "$student_folder" -type f -name "$student_id.*" | head -n 1)

    if [ -z "$submission_file" ]; then
        # marks_deducted=$((marks_deducted + submission_violation_penalty))
        echo "$student_id,0,$marks_deducted,$total_marks,$remarks" >>marks.csv
        continue
    fi

    # Verifying allowed language
    if [[ ! " $allowed_languages " =~ "${submission_file##*.}" ]]; then
        remarks="$remarks issue case #3"
        marks_deducted=$((marks_deducted + submission_violation_penalty))
        echo "$student_id,0,0,$total_marks,$remarks" >>marks.csv
        continue
    fi

    # Running file and generating output
    output_file="$student_folder/${student_id}_output.txt"

    if [[ "${submission_file##*.}" == "c" || "${submission_file##*.}" == "cpp" ]]; then
        g++ "$submission_file" -o "$student_folder/$student_id.out" &>/dev/null
        "$student_folder/$student_id.out" >"$output_file" 2>/dev/null
    elif [[ "${submission_file##*.}" == "py" ]]; then
        python3 "$submission_file" >"$output_file" 2>/dev/null
    elif [[ "${submission_file##*.}" == "sh" ]]; then
        bash "$submission_file" >"$output_file" 2>/dev/null
    fi

    # Creating and matching student_output_file
    generated_output="$output_file"
    expected_output_file="$expected_output_file_location"

    unmatched_lines=$(grep -Fxvf "$expected_output_file" "$generated_output" | wc -l)
    marks_deducted=$((marks_deducted + unmatched_lines * unmatched_output_penalty))

    # Deduction for plagiarism
    if grep -q "$student_id" "$plagiarism_file"; then
        remarks="$remarks plagiarism detected"
        marks_deducted=$((marks_deducted + plagiarism_penalty))
    fi

    # Writing final marks to csv file
    final_marks=$((total_marks - marks_deducted))
    echo "$student_id,$total_marks,$marks_deducted,$final_marks,$remarks" >>marks.csv

    # Adding file to issues folder
    if [ -n "$remarks" ]; then
        cp "$student_file" issues/
        # rm -r "$student_folder"
    fi
done

# Adding missing submission to remarks
for ((i = 0; i < number_of_students; i++)); do
    if [ "${bool_array[i]}" -eq 0 ]; then
        student_id=$((student_id_start + i))
        remarks="missing submission"
        echo "$student_id,0,0,100,$remarks" >>marks.csv
        continue
    fi
done

# Sorting the csv file by id
{ head -n 1 marks.csv && tail -n +2 marks.csv | sort -t, -k1,1; } > temp.csv && mv temp.csv marks.csv