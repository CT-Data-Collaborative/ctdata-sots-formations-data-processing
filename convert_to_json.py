import os
import json, csv
import argparse

def is_dir(base, p):
    return os.path.isdir(os.path.join(base, p))

def get_csv_file_list(directory):
    return [f for f in os.listdir(directory) if f.endswith(".csv")]

def get_directory_list(directory):
    path_list = [directory]
    for d in os.listdir(directory):
        if is_dir(directory, d):
            path_list.append(os.path.join(directory, d))
    return path_list


def load_from_csv(data_file_path):
    data = []
    with open(data_file_path) as csvFile:
        csvReader = csv.DictReader(csvFile)
        for row in csvReader:
            o = {}
            for k, v in row.iteritems():
                k = k.decode("utf-8").strip()
                v = v.decode("utf-8").strip()
                if v == "null":
                    v = None
                # if "FIPS" in k:
                #     v = "0"+str(v)
                o[k] = v
            data.append(o)
    return data

def convert(data_dirs, input, output):
    for data_dir in data_dirs:
        OUTPUT_DIR = data_dir.replace(input, output)
        data_files = get_csv_file_list(data_dir)
        for data_file in data_files:
            output_file = data_file.replace("csv", "json")
            print(output_file)
            data = load_from_csv(os.path.join(data_dir, data_file))
            if not os.path.exists(OUTPUT_DIR):
                os.makedirs(OUTPUT_DIR)
            with open(os.path.join(OUTPUT_DIR, output_file), "w") as jsonFile:
                json.dump(data, jsonFile)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input", help="Specfify input directory")
    parser.add_argument("-o", "--output", help="Specfify output directory")
    parser.add_argument("-c", "--convert", action="store_true", help="Convert files")
    args = parser.parse_args()
    if args.input:
        data_dirs = get_directory_list(args.input)
    else:
        raise SystemExit("error: No input directory provided")
    if args.output:
        if not os.path.exists(args.output):
            msg = 'invalid output directory. {} does not exist.'.format(args.output)
            raise SystemExit(args.output, msg)
        else:
            if args.convert:
                convert(data_dirs, args.input, args.output)
            else:
                raise SystemExit("dry run")
    else:
        raise SystemExit("error: No output directory provided")


