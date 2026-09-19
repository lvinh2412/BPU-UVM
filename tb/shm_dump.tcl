database -open waves -into waves.shm -default
probe -create -shm bpu_hw_top -all -depth all -memories
run
exit
