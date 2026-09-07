#!/bin/bash

SESSION="sim_runs"

# Kill existing session (optional but recommended)
tmux kill-session -t $SESSION 2>/dev/null

# Create new detached session
tmux new-session -d -s $SESSION

# Helper function to create window + run command
run_in_window () {
    local name=$1
    local cmd=$2

    tmux new-window -t $SESSION -n "$name"
    tmux send-keys -t $SESSION:"$name" "$cmd" C-m
}

# Launch all jobs
run_in_window coremark    "scons sim PROFILE=coremark_tb PROG='tests/coremark_im.elf'"
run_in_window aes_sha     "scons sim PROFILE=aes_sha_tb PROG='tests/cp3_release_benches/im/aes_sha.elf'"
run_in_window compression "scons sim PROFILE=compression_tb PROG='tests/cp3_release_benches/im/compression.elf'"
run_in_window fft         "scons sim PROFILE=fft_tb PROG='tests/cp3_release_benches/im/fft.elf'"
run_in_window mergesort   "scons sim PROFILE=mergesort_tb PROG='tests/cp3_release_benches/im/mergesort.elf'"
run_in_window image       "scons sim PROFILE=image_tb PROG='tests/cp3_release_benches/im/image.elf'"

# Attach to session
tmux attach-session -t $SESSION