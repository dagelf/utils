import gzip
from glob import glob
from datetime import datetime

def read_log_files(log_pattern):
    log_files = sorted(glob(log_pattern), reverse=True)
    log_lines = []

    for log_file in log_files:
        if log_file.endswith('.gz'):
            with gzip.open(log_file, 'rt') as f:
                log_lines.extend(f.readlines())
        else:
            with open(log_file, 'r') as f:
                log_lines.extend(f.readlines())

    return log_lines

def filter_command_entries(apt_lines):
    command_entries = []

    for idx, line in enumerate(apt_lines):
        if line.startswith('Commandline:'):
            date_line = apt_lines[idx - 1]
            date_str = date_line.split()[1]  # Extract date string

#            # Check if the time component is missing and add a default time value
#            if len(date_str) <= 10:  # The length of 'YYYY-MM-DD' is 10
#                date_str += " 00:00:00"
#
#            date = datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
#            command_entries.append((date, line.strip()))
            command_entries.append((date_str, line.strip()))

    return command_entries

def main():
    apt_lines = read_log_files('/var/log/apt/history.log*')
    command_entries = filter_command_entries(apt_lines)

    for date, command in command_entries:
        print(f"{date} {command}")

if __name__ == "__main__":
    main()
