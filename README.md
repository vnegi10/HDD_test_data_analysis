## HDD_test_data_analysis

In this Pluto notebook, we will analyze hard drive S.M.A.R.T. data graciously provided by
Backblaze. The quaterly CSV data are bundled together into a zipped file, which
can be downloaded from [here.](https://www.backblaze.com/b2/hard-drive-test-data.html)

## Data

HDD S.M.A.R.T. data has been made available by Backblaze for free and non-profit use. Due to 
the large size of each quarterly dataset (~ 7.1 GB), they are not added here. Make sure to 
first download and extract them into a "data" folder within the root of this cloned repository.
Definition of various S.M.A.R.T. attributes can be found [here.](http://ntfs.com/disk-monitor-smart-attributes.htm)

## How to use?

Install Pluto.jl (if not done already) by executing the following commands in your Julia REPL:

    using Pkg
    Pkg.add("Pluto")
    using Pluto
    Pluto.run() 

Clone this repository and open **HDD_test_data_analysis** in your Pluto browser window. That's it! 
You are good to go.