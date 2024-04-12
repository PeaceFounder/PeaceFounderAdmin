module LocalSync

function isequal_files(file1::String, file2::String; chunk_size = 8192)::Bool
    # Open both files in read-only binary mode
    open(file1, "r") do f1
        open(file2, "r") do f2
            # Read and compare chunks of the files until the end of either file is reached
            while !eof(f1) && !eof(f2)
                # Read a chunk from each file
                chunk1 = read(f1, chunk_size)  # Adjust chunk size as needed
                chunk2 = read(f2, chunk_size)

                # Compare the chunks
                if chunk1 != chunk2
                    return false
                end
            end

            # Ensure both files reached EOF together, indicating they are of the same length
            return eof(f1) && eof(f2)
        end
    end
end


function hardlink_recursively(src::String, dest::String; overwrite=false, verbose=false, dry_run=false)

    mkpath(dest)

    for (root, dirs, files) in walkdir(src)

        root_relpath = root == src ? "" : relpath(root, src)

        for dir in dirs
            dir_path = joinpath(dest, root_relpath, dir)
            isdir(dir_path) || mkdir(dir_path)
        end

        for file in files

            src_path = joinpath(root, file)
            dest_path = joinpath(dest, root_relpath, file)
            
            if isfile(dest_path)

                if Sys.isunix() && stat(src_path).inode == stat(dest_path).inode
                    verbose && println("File is already present and is hardlinked to the source: $dest_path")
                    continue
                end
                
                if isequal_files(src_path, dest_path)
                    verbose && println("File is already present and identical: $dest_path")
                    continue
                else
                    if overwrite
                        dry_run || rm(dest_path)
                    else
                        continue
                    end
                end
            end

            dry_run || hardlink(src_path, dest_path)
            verbose && println("Hard linked $src_path to $dest_path")
        end
    end

    return
end


function clean_destination(src::String, dest::String; dry_run=false, verbose=false)

    isdir(dest) || return
    
    for (root, dirs, files) in walkdir(dest, topdown=false)

        root_relpath = root == dest ? "" : relpath(root, dest)

        for dir in dirs
            if !isdir(joinpath(src, root_relpath, dir))
                path = joinpath(root, dir)
                dry_run || rm(path)
                verbose && println("$path not found in $src")
            end
        end

        for file in files
            if !isfile(joinpath(src, root_relpath, file))
                path = joinpath(root, file)
                dry_run || rm(path)
                verbose && println("$path not found in $src")
            end
        end
    end

    return
end


function sync(src::String, dest::String; dry_run=false, verbose=false)

    clean_destination(src, dest; dry_run, verbose)
    hardlink_recursively(src, dest; overwrite=true, dry_run, verbose)

    return
end


end
