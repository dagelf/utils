import re
from datetime import datetime

#def read_dpkg_log():
#    with open('/var/log/dpkg.log', 'r') as f:
#        return f.readlines()

import gzip
from glob import glob
def read_dpkg_log():
    log_files = ['/var/log/dpkg.log'] + sorted(glob('/var/log/dpkg.log.*.gz'), reverse=True)
    log_lines = []

    for log_file in log_files:
        if log_file.endswith('.gz'):
            with gzip.open(log_file, 'rt') as f:
                log_lines.extend(f.readlines())
        else:
            with open(log_file, 'r') as f:
                log_lines.extend(f.readlines())

    return log_lines

def filter_install_entries(log_lines):
    return [line for line in log_lines if ' install ' in line]

def extract_package_info(install_lines):
    package_info = []
    for line in install_lines:
        parts = line.split()
        date_str = f"{parts[0]} {parts[1]}"
        date = datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
        package_name = parts[3]
        package_info.append((date, package_name))
    return package_info

def sort_packages_by_date(package_info):
    return sorted(package_info, key=lambda x: x[0])

def main():
    log_lines = read_dpkg_log()
    install_lines = filter_install_entries(log_lines)
    package_info = extract_package_info(install_lines)
    sorted_packages = sort_packages_by_date(package_info)

    for date, package_name in sorted_packages:
        print(f"{date} {package_name}")

if __name__ == "__main__":
    main()
