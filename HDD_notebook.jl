### A Pluto.jl notebook ###
# v0.19.22

using Markdown
using InteractiveUtils

# ╔═╡ 0f13e168-a1a3-11ed-1d08-6d1b9fd20152
using CSV, DataFrames, Dates, VegaLite, ThreadsX, Statistics

# ╔═╡ 526df6c0-92e6-40f9-96b8-8400e172c44a
md"
### Load packages
---
"

# ╔═╡ a5fb7e11-38ca-49a3-87a8-35afd5d8ed1b
md"
### Read files
---
"

# ╔═╡ 8624f4f9-a9f6-4938-ad73-a3e279eaa93b
function read_filepaths(folder::String)

	filepaths = String[]

	for (root, dirs, files) in walkdir(folder)
		for file in files
			if endswith(file, ".csv")
				push!(filepaths, joinpath(root, file))
			end
		end		
	end

	return filepaths
end

# ╔═╡ 9362eaad-ff3e-437f-bd6e-5515a913641f
function csv_to_df(file)
	df_hdd = CSV.File(file, header = 1) |> DataFrame
	return df_hdd
end

# ╔═╡ 3cb20b83-935e-4766-99d1-0d25a0becdce
files = read_filepaths("data/2022")

# ╔═╡ 89cb4259-9724-4c12-a587-da43028c1750
@time df_hdd = csv_to_df(files[1])

# ╔═╡ c91e5550-37b7-4cf9-b8b5-7aeb1957e524
df_nok = filter(row -> row.failure > 0, df_hdd)

# ╔═╡ eddc27e9-fe8e-490e-b849-52e32dd7019d
md"
##### Test serial vs parallel implementation
"

# ╔═╡ 324fe9f0-b3f6-4345-98e8-2bf66e5fe893
function get_all_df_serial(location::String, num_files::Int64)

	files = read_filepaths(location)
	files_to_use = files[1:num_files]

	all_hdd = Array{DataFrame}(undef, length(files_to_use))
	
	map!(x -> csv_to_df(x), all_hdd, files_to_use)

	return all_hdd
end	

# ╔═╡ f5cbdb7a-b215-44ba-b01b-d4bae48ba106
function get_all_df_parallel(location::String, num_files::Int64)

	files = read_filepaths(location)
	files_to_use = files[1:num_files]

	all_hdd = Array{DataFrame}(undef, length(files_to_use))
	
	ThreadsX.map!(x -> csv_to_df(x), all_hdd, files_to_use)

	return all_hdd
end	

# ╔═╡ db8e7773-9ead-48ba-829a-2ef9b7710a1d
md"
### Explore data
---
"

# ╔═╡ d7c35096-e9d2-4881-9a55-783ecc49d612
names(df_hdd)

# ╔═╡ 05a82650-9f18-4b77-b54c-3fd587e56522
md"
##### Population health based on SMART 5, 187, 188
"

# ╔═╡ 6aca02ac-0b48-4643-b18b-6b9f26677881
function get_population_health(location::String, num_files::Int64)

	files = read_filepaths(location)
	files_to_use = files[1:num_files]
	
	dates = Date[]
	noks  = Float64[]

	for file in files_to_use
		df_hdd = csv_to_df(file)
		num_total = nrow(df_hdd)

		# Get first value as all dates are same
		push!(dates, df_hdd[!, :date][1])

		# Filter relevant columns
		df_hdd = select(df_hdd, [:smart_5_raw, 
		                         :smart_187_raw,
		                         :smart_188_raw],
		                         copycols = false)

		num_nok = count(row -> ~ismissing(row.smart_5_raw) && 
		      				   ~ismissing(row.smart_187_raw) &&
			                   ~ismissing(row.smart_188_raw) &&
		                       row.smart_5_raw > 0 &&
			                   row.smart_187_raw > 0 &&
			                   row.smart_188_raw > 0,
			                   eachrow(df_hdd))
		
		fraction_nok = (num_nok / num_total) * 100
		push!(noks, fraction_nok)
	end

	df_health = DataFrame(DATES = dates, 
	                      NOKS  = noks)

end

# ╔═╡ 510ae8dc-2288-4927-9552-782fc98dd290
function get_health(file)

	df_hdd = csv_to_df(file)
	num_total = nrow(df_hdd)

	date = df_hdd[!, :date][1]

	num_nok = ThreadsX.count(row -> ~ismissing(row.smart_5_raw) && 
		      				   ~ismissing(row.smart_187_raw) &&
			                   ~ismissing(row.smart_188_raw) &&
		                       row.smart_5_raw > 0 &&
			                   row.smart_187_raw > 0 &&
			                   row.smart_188_raw > 0,
			                   eachrow(df_hdd))
	
	fraction_nok = (num_nok / num_total) * 100

	return DataFrame(DATES = date, NOKS = fraction_nok)
	
end

# ╔═╡ 5a8890a3-6d0a-495a-b261-9b68933b95a2
function get_population_health_parallel(location::String, num_files::Int64)

	files = read_filepaths(location)
	files_to_use = files[1:num_files]

	all_health = Array{DataFrame}(undef, length(files_to_use))
	
	ThreadsX.map!(x -> get_health(x), all_health, files_to_use)

	return vcat(all_health...)
end	

# ╔═╡ 0ae085ec-ec13-4f26-b6f2-4bf7d264865f
#@time get_population_health("data", 60)

# ╔═╡ fbf2b366-b36e-4f2e-9ffb-2a2bedf9305a
#@time get_population_health_parallel("data", 60)

# ╔═╡ 00ab4336-e085-4c18-b868-09986348205d
md"
##### Drive failure correlation with SMART parameters
"

# ╔═╡ 6cb90013-5e91-435f-bfac-85eccb13d4f4
function get_stat_match(df::DataFrame, smart_stat::String)

	num_total   = nrow(df)

	df_stat     = select(df, Symbol(smart_stat) => Symbol("to_check"))
	num_stat    = count(row -> ~ismissing(row.to_check) && 
	                                      row.to_check > 0, eachrow(df_stat))

	num_match   = (num_stat / num_total) * 100

	return num_match
end

# ╔═╡ 570c59ec-31aa-475a-9284-eba9418ed2e6
function get_parameter_split(location::String, 
	                         num_files::Int64;
                             smart_stat::String)

	files = read_filepaths(location)
	files_to_use = files[1:num_files]

	dates = Date[]
	nok_match, ok_match = [Float64[] for i = 1:2]	

	for file in files_to_use

		df_hdd = file |> csv_to_df
		push!(dates, df_hdd[!, :date][1])
	
		df_nok = filter(row -> ~ismissing(row.failure) && 
		                                  row.failure > 0, df_hdd)
		df_ok  = filter(row -> ~ismissing(row.failure) &&
		                                  row.failure == 0, df_hdd)
	
		# % of failed drives showing SMART stat > 0
		nok = get_stat_match(df_nok, smart_stat)	
		push!(nok_match, nok)
	
		# % of operational drives showing SMART stat > 0
		ok  = get_stat_match(df_ok, smart_stat)
		push!(ok_match, ok)

	end

	df_stats = DataFrame(DATES = dates, 
	                     FAILED = nok_match,
	                     OPERATIONAL  = ok_match)

	return df_stats
end	

# ╔═╡ 1c551031-d877-4327-9bcd-6380682ff190
#df_stats = get_parameter_split("data", 15, smart_stat = "smart_7_raw")

# ╔═╡ f8e20f63-eb07-48df-9fa1-617ab49697e7
md"
##### Collect data for failed drives
"

# ╔═╡ 9fc66684-1f99-4d5f-8cce-c5c4899bfa8b
function get_failed_drives(location::String, 
	                       num_files::Int64)

	files = read_filepaths(location)
	@assert num_files ≤ length(files) "Reduce the number of files below $(length(files))"
	
	files_to_use = files[1:num_files]
	all_nok = DataFrame[]

	for file in files_to_use
		df_hdd = file |> csv_to_df

		df_nok = filter(row -> ~ismissing(row.failure) && 
		                                  row.failure > 0, df_hdd)

		push!(all_nok, df_nok)
	end

	return vcat(all_nok...)
	
end	

# ╔═╡ 4dba1e91-f86e-496e-a595-2710e7c5b93f
function filter_failures(file::String)

	df_hdd = file |> csv_to_df
	df_nok = filter(row -> ~ismissing(row.failure) && 
		                              row.failure > 0, df_hdd)

	return df_nok
end

# ╔═╡ a6c357d8-db82-4820-ac81-e650d787cf54
function get_failed_drives_parallel(location::String, 
	                       			num_files::Int64)

	files = read_filepaths(location)
	@assert num_files ≤ length(files) "Reduce the number of files below $(length(files))"
	
	files_to_use = files[1:num_files]
	all_nok = Array{DataFrame}(undef, length(files_to_use))

	ThreadsX.map!(x -> filter_failures(x), all_nok, files_to_use)

	return vcat(all_nok...)

end	

# ╔═╡ 6c80ce03-dd0d-4d4a-883e-8bfc34e71009
@time df_all_nok = get_failed_drives("data/2022", 10) 

# ╔═╡ 54c1df98-0f66-4150-bc38-39ed1d9689e6
#@time df_all_nok_1 = get_failed_drives_parallel("data/2022", 180)

# ╔═╡ b534f5eb-90ce-44ae-86ae-061e91c56bf4
md"
##### Count number of each model
"

# ╔═╡ 9c227e4f-5663-4423-84a9-1862458c591f
function get_model_count(df_hdd::DataFrame)
	
	# Get count of each model
	all_models = df_hdd[!, :model] |> unique
	all_counts = Int64[]

	for model in all_models
		num_counts = count(x -> x == model, df_hdd[!, :model])
		push!(all_counts, num_counts)
	end

	df_hdd_model = DataFrame(MODELS = all_models, 
	                         COUNTS = all_counts)

	return df_hdd_model
end

# ╔═╡ af765635-304c-4688-a412-ff12a5554885
begin
	df_model_count = get_model_count(df_hdd)
	sort(df_model_count, :COUNTS, rev = true)
end

# ╔═╡ 27f2a510-9e43-4f56-8deb-144164cc9e1e
md"
### Plot data
---
"

# ╔═╡ a7ce54f2-ec66-43ab-823b-50834369bf3f
md"
##### Capacity distribution on a given day
"

# ╔═╡ abf0af13-6028-4ca7-8736-0947429639d2
function plot_capacity_dist(location::String, file_index::Int64)

	files  = read_filepaths(location)
	@assert file_index ≤ length(files) "Select a lower index"
	
	df_hdd = CSV.File(files[file_index], header = 1) |> DataFrame
	df_hdd = filter(row -> ~ismissing(row.capacity_bytes) &&
		            row.capacity_bytes > 0, df_hdd)

	day = df_hdd[!, :date][1]	

	df_hdd_capacity = select(df_hdd, 
		                     :model, 
		                     :capacity_bytes => (x -> x / 1e12) => :capacity_TB)

	figure = df_hdd_capacity |>

	@vlplot(:bar, 
	        x = {:capacity_TB, 
		         "axis" = {"title" = "HDD capacity [TB]", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}, 
	             "bin" = {"maxbins" = 25}},
				 
	        y = {"count()", 
			     "axis" = {"title" = "Number of counts", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}},
						   
	        width   = 750, 
			height  = 500, 
			"title" = {"text" = "HDD capacity distribution on $(day)", 
			           "fontSize" = 12},
			color = :model
			)

	return figure

end

# ╔═╡ 954ede07-53c7-4b64-bba4-4072c6e43863
figure2 = plot_capacity_dist("data/2022/data_Q1_2022/", 10)

# ╔═╡ cf704ae2-8a2b-49ea-a1ac-23a60a9c3666
md"
##### Capacity distribution for all failed drives
"

# ╔═╡ 1c321919-8ee2-4472-8979-66b7eb29f52d
function plot_failed_capacity_dist(location::String, 
	                      		   num_files::Int64)

	df_all_nok = get_failed_drives(location, num_files)

	start_date, end_date = df_all_nok[!, :date][1], df_all_nok[!, :date][end]

	df_hdd_capacity = select(df_all_nok, 
		                     :model, 
		                     :capacity_bytes => (x -> x / 1e12) => :capacity_TB)

	figure = df_hdd_capacity |>

	@vlplot(:bar, 
	        x = {:capacity_TB, 
		         "axis" = {"title" = "HDD capacity [TB]", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}, 
	             "bin" = {"maxbins" = 25}},
				 
	        y = {"count()", 
			     "axis" = {"title" = "Number of counts", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}},
						   
	        width   = 750, 
			height  = 500, 
			"title" = {"text" = "Failed HDD capacity distribution between $(start_date) and $(end_date)", 
			           "fontSize" = 12},
			color = :model
			)

	return figure
end	

# ╔═╡ 6458cb46-7e17-4b92-87fd-d09125db5498
#figure1 = plot_failed_capacity_dist("data/2022/", 365)

# ╔═╡ af68db74-0447-41cf-87a6-d8cdb8c0d82c
md"
##### Model distribution for a given day
"

# ╔═╡ 860f4a45-8c8a-46b0-9bf3-fd505a34196e
function plot_model_dist(location::String, file_index::Int64)

	files  = read_filepaths(location)
	@assert file_index ≤ length(files) "Select an index lesser than $(length(files))"
	
	df_hdd = csv_to_df(files[file_index])

	day = df_hdd[!, :date][1]

	df_hdd_model = get_model_count(df_hdd)

	figure = df_hdd_model |>

	@vlplot(:bar, 
	        x = {:MODELS, 
		         "axis" = {"title" = "HDD model ", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12,
						   "labelAngle" = 90}},
				 
	        y = {:COUNTS, 
			     "type" = "quantitative",
			     "axis" = {"title" = "Number of counts", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}},
						   
	        width   = 750, 
			height  = 500, 
			"title" = {"text" = "All HDD model distribution on $(day)", 
			           "fontSize" = 12},
			)

	return figure
	
end

# ╔═╡ 52d3fdd8-e078-45c8-9e81-9ee4bd6531e9
#plot_model_dist("data/2022", 1)

# ╔═╡ 5cc69e6a-4f9f-43fb-8cc7-f1062491de2e
md"
##### Model distribution for failed drives
"

# ╔═╡ 445285b9-643b-4f64-a9ea-6f97d5b009e2
function plot_failed_model_dist(location::String, 
	                      		num_files::Int64)

	df_all_nok = get_failed_drives(location, num_files)

	start_date, end_date = df_all_nok[!, :date][1], df_all_nok[!, :date][end]

	df_hdd_model = get_model_count(df_all_nok)

	figure = df_hdd_model |>

	@vlplot(:bar, 
	        x = {:MODELS, 
		         "axis" = {"title" = "HDD model ", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12,
						   "labelAngle" = 45}},
				 
	        y = {:COUNTS, 
			     "type" = "quantitative",
			     "axis" = {"title" = "Number of counts", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}},
						   
	        width   = 750, 
			height  = 500, 
			"title" = {"text" = "Failed HDD model distribution between $(start_date) and $(end_date)", 
			           "fontSize" = 12},
			)

	return figure
end	

# ╔═╡ 0367be00-5fc5-4973-bfd2-e042ba21714a
#plot_failed_model_dist("data/2022/", 365)

# ╔═╡ 505c2151-3a55-41ca-a1fa-d41ef97cde54
function plot_failed_model_pert(location::String, 
	                      		num_files::Int64)

	files  = read_filepaths(location)

	# Read first file to get a population sample
	df_hdd = csv_to_df(files[1])
	df_hdd_model = get_model_count(df_hdd)

	# Get total failed drives
	df_all_nok = get_failed_drives(location, num_files)
	start_date, end_date = df_all_nok[!, :date][1], df_all_nok[!, :date][end]

	df_nok_model = get_model_count(df_all_nok)
	allowmissing!(df_nok_model)
	
	all_nok_pert = Union{Float64, Missing}[]

	for (i, model) in enumerate(df_nok_model[!, :MODELS])

		try
			df_total = filter(row -> row.MODELS == model, df_hdd_model)
			num_total = df_total[!, :COUNTS][1]

			nok_pert = (df_nok_model[!, :COUNTS][i] / num_total) * 100
			push!(all_nok_pert, nok_pert)
		catch
			push!(all_nok_pert, missing)
		end
		
	end

	insertcols!(df_nok_model, 2, :PERT => all_nok_pert, after = true)

	figure = df_nok_model |>

	@vlplot(:bar, 
	        x = {:MODELS, 
		         "axis" = {"title" = "HDD model ", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12,
						   "labelAngle" = 45}},
				 
	        y = {:PERT, 
			     "type" = "quantitative",
			     "axis" = {"title" = "% of total number of drives of same type", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}},
						   
	        width   = 750, 
			height  = 500, 
			"title" = {"text" = "Failed HDD model % distribution between $(start_date) and $(end_date)", 
			           "fontSize" = 12},
			)

	return figure

end	

# ╔═╡ f844f06a-0a53-481d-a642-7816224ec649
#figure3 = plot_failed_model_pert("data/2022", 365)

# ╔═╡ 0542e747-1bd7-4df1-918c-2a6be441ae34
md"
##### Correlation between SMART parameters for failed drives
"

# ╔═╡ efd4108f-abc5-4b8f-b923-d63b351ed8b9
function plot_failed_corr(location::String, 
	                      num_files::Int64;
                          s1::String,
                          s2::String)

	df_all_nok = get_failed_drives(location, num_files)
	start_date, end_date = df_all_nok[!, :date][1], df_all_nok[!, :date][end]

	figure = df_all_nok |>
	
	@vlplot(:circle, 
	        x = {Symbol(s1),
		         bin  = {maxbins = 10},		
		         axis = {"title" = "$(s1) parameter", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}},
				 
	        y = {Symbol(s2),
			     bin  = {maxbins = 10},	
			     axis = {"title" = "$(s2) parameter", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 12}},

			size = "count()",
						   
	        width   = 750, 
			height  = 500, 
			
			"title" = {"text" = "2D histogram scatterplot for failed drives between $(start_date) and $(end_date)", 
			"fontSize" = 12}
			)

	return figure
	
end	

# ╔═╡ 764aec64-93fe-4253-923c-82b0c6ef7ab2
function plot_failed_scatter(location::String, 
	                      	 num_files::Int64;
                             s1::String,
                             s2::String)

	df_all_nok = get_failed_drives(location, num_files)
	start_date, end_date = df_all_nok[!, :date][1], df_all_nok[!, :date][end]

	# Calculate Pearson's correlation coefficient
	df_corr     = select(df_all_nok, [Symbol(s1), Symbol(s2)]) |> dropmissing
	correlation = cor(df_corr[!, 1], df_corr[!, 2])
	correlation = round(correlation, digits = 3)

	figure = df_all_nok |>
	
	@vlplot(:point, 
	        x = {Symbol(s1),
		         axis = {title = "$(s1) parameter", 
				         labelFontSize = 12, 
						 titleFontSize = 12}},
				 
	        y = {Symbol(s2),
			     axis = {title = "$(s2) parameter", 
				         labelFontSize = 12, 
						 titleFontSize = 12}},
						 
	        width   = 750, 
			height  = 500, 
			
			"title" = {"text" = "2D scatterplot for failed drives between $(start_date) and $(end_date), Pearson's corr. coeff. = $(correlation)", 
			"fontSize" = 12}
			)

	return figure
	
end	

# ╔═╡ 27f02918-ab29-4df5-9c7a-e61997d1013b
figure8 = plot_failed_scatter("data/2022", 365, s1 = "smart_197_raw", s2 = "smart_198_raw")

# ╔═╡ 3f9287e3-a09c-4516-ac74-82da80ec6519
#plot_failed_corr("data/2022", 180, s1 = "smart_197_raw", s2 = "smart_198_raw")

# ╔═╡ d81b74eb-5014-481c-a0bc-979f5f6fb564
#figure9 = plot_failed_scatter("data/2022", 365, s1 = "smart_187_raw", s2 = "smart_197_raw")

# ╔═╡ 031e7ec2-41ff-477e-a27e-f4548bbda7b9
md"
##### Distribution of crucial SMART parameters between operational and failed drives
"

# ╔═╡ 72749fd6-8cdb-450a-86e1-be55ea8688b5
function plot_parameter_split(location::String, 
	                          num_files::Int64;
                              smart_stat::String)

	df_split = get_parameter_split(location, num_files, smart_stat = smart_stat)

	nok_share = mean(df_split[!, :FAILED])
	nok_share = round(nok_share, digits = 2)
	
	ok_share  = mean(df_split[!, :OPERATIONAL])
	ok_share  = round(ok_share, digits = 2)	

	sdf_split = stack(df_split, 
		              [:FAILED, :OPERATIONAL],
	                  variable_name = :STATUS,
	                  value_name    = :SHARE)

	figure = sdf_split |>
	@vlplot(mark = {"type" = "bar",
	                 width = 25},

			column = "DATES:o",

			x = {:STATUS, 
		         "axis" = {"title" = "", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 14},
				 "labelAngle" = 45},

	        y = {:SHARE,
			     "axis" = {"title" = "% of drives reporting $(smart_stat) > 0", 
				           "labelFontSize" = 12, 
						   "titleFontSize" = 14}},

			width   = 50, 
			height  = 500, 
			
			title = {"text" = "Distribution of $(smart_stat) > 0 between operational ($(ok_share) %) and failed ($(nok_share) %) drives", 
			         "anchor" = "middle",
			         "fontSize" = 18},
					 
			color = {:STATUS, 
			         scale = {domain = ["FAILED", "OPERATIONAL"],
				             range   = [ :red, :green]},
					 legend = false},

			spacing = 10,
			config  = {view = {stroke = :transparent},
			           axis = {domainWidth = 1}},
			)

	return figure
end

# ╔═╡ 24781723-f438-4cfd-8163-5bdd1f39b6bc
md"
##### 05 - Reallocated Sectors Count
Count of reallocated sectors. When the hard drive finds a read/write/verification error, it marks this sector as \"reallocated\" and transfers data to a special reserved area (spare area). This process is also known as remapping and \"reallocated\" sectors are called remaps. This is why, on modern hard disks, \"bad blocks\" cannot be found while testing the surface — all bad blocks are hidden in reallocated sectors. However, the more sectors that are reallocated, the more read/write speed will decrease.
"

# ╔═╡ c54a6985-5262-456d-ae9a-e0fb13106d84
figure4 = plot_parameter_split("data/2022/data_Q1_2022/", 15, smart_stat = "smart_5_raw")

# ╔═╡ 3f45d54a-9d70-42c5-aa23-214d516023b4
md"
##### 07 - Seek Error Rate
Rate of seek errors of the magnetic heads. If there is a failure in the mechanical positioning system, a servo damage or a thermal widening of the hard disk, seek errors arise. More seek errors indicates a worsening condition of a disk surface and the mechanical subsystem.
"

# ╔═╡ 42672886-0154-4014-b69d-8f470d973c04
#figure5 = plot_parameter_split("data/2022/data_Q1_2022/", 15, smart_stat = "smart_7_raw")

# ╔═╡ 660dc65d-42eb-477b-84f7-197d6b56c6ad
md"
##### 187 - Reported Uncorrectable Errors
"

# ╔═╡ 4e8bf324-7d1d-4550-956a-1eb1d87c28c8
#plot_parameter_split("data/2022/data_Q1_2022/", 15, smart_stat = "smart_187_raw")

# ╔═╡ e4f67c5c-dabc-4c78-a113-097d912e6a60
md"
##### 196 - Reallocation Event Count
Count of remap operations. The raw value of this attribute shows the total number of attempts to transfer data from reallocated sectors to a spare area. Both successful & unsuccessful attempts are counted.
"

# ╔═╡ 54d11ae3-9272-4087-858b-1f7d18bd6fdd
#plot_parameter_split("data/data_Q4_2021/", 15, smart_stat = "smart_196_raw")

# ╔═╡ 58b5cc2a-240a-4486-9fa7-8fc73b43f65c
md"
##### 197 - Current Pending Sector Count
Number of \"unstable\" sectors (waiting to be remapped). If the unstable sector is subsequently written or read successfully, this value is decreased and the sector is not remapped. Read errors on the sector will not remap the sector, it will only be remapped on a failed write attempt. This can be problematic to test because cached writes will not remap the sector, only direct I/O writes to the disk.
"

# ╔═╡ 974eb941-73c6-41c3-881d-2b9ce4b5b950
figure6 = plot_parameter_split("data/2022/data_Q4_2022", 15, smart_stat = "smart_197_raw")

# ╔═╡ cfe4a08c-7b96-4ce0-920e-5d397c889c80
#plot_parameter_split("data/data_Q4_2021/", 15, smart_stat = "smart_197_raw")

# ╔═╡ 68f57dcf-5c07-4249-9f52-4308f8e997a2
md"
##### 198 - Uncorrectable Sector Count
The total number of uncorrectable errors when reading/writing a sector. A rise in the value of this attribute indicates defects of the disk surface and/or problems in the mechanical subsystem.
"

# ╔═╡ bfe33c3d-7766-410d-8f74-4739fe498525
#figure7 = plot_parameter_split("data/2022/data_Q2_2022", 15, smart_stat = "smart_198_raw")

# ╔═╡ 4efd1e1e-a9da-45b9-bf70-7bb9b2c9aad9
md"
##### 199 - UltraDMA CRC Error Count
The number of errors in data transfer via the interface cable as determined by ICRC (Interface Cyclic Redundancy Check).
"

# ╔═╡ d683edf1-dd0e-424e-a32f-66c5baaad975
#plot_parameter_split("data/data_Q4_2022/", 15, smart_stat = "smart_199_raw")

# ╔═╡ 8190950a-75dd-45cd-ae9b-28f3b29c4cdb
#plot_parameter_split("data/data_Q4_2021/", 15, smart_stat = "smart_199_raw")

# ╔═╡ e0022d18-4cbf-462d-8936-f187e5836432
md"
##### 200 - Write Error Rate / Multi-Zone Error Rate
The total number of errors when writing a sector.
"

# ╔═╡ a711fbc9-40cc-4b57-997c-33f45d50fcba
plot_parameter_split("data/2022/data_Q3_2022/", 15, smart_stat = "smart_200_raw")

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
ThreadsX = "ac1d9e8a-700a-412c-b207-f0111f4b6c0d"
VegaLite = "112f6efa-9a02-5b7d-90c0-432ed331239a"

[compat]
CSV = "~0.10.9"
DataFrames = "~1.4.4"
ThreadsX = "~0.1.11"
VegaLite = "~2.6.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.8.5"
manifest_format = "2.0"
project_hash = "7b041109739619654c81d3ff974eb0ee9c870995"

[[deps.Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "0310e08cb19f5da31d08341c6120c047598f5b9c"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.5.0"

[[deps.ArgCheck]]
git-tree-sha1 = "a3a402a35a2f7e0b87828ccabbd5ebfbebe356b4"
uuid = "dce04be8-c92d-5529-be00-80e4d2c0e197"
version = "2.3.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.BangBang]]
deps = ["Compat", "ConstructionBase", "Future", "InitialValues", "LinearAlgebra", "Requires", "Setfield", "Tables", "ZygoteRules"]
git-tree-sha1 = "7fe6d92c4f281cf4ca6f2fba0ce7b299742da7ca"
uuid = "198e06fe-97b7-11e9-32a5-e1d131e6ad66"
version = "0.3.37"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.Baselet]]
git-tree-sha1 = "aebf55e6d7795e02ca500a689d326ac979aaf89e"
uuid = "9718e550-a3fa-408a-8086-8db961cd8217"
version = "0.1.1"

[[deps.BitFlags]]
git-tree-sha1 = "43b1a4a8f797c1cddadf60499a8a077d4af2cd2d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.7"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "SnoopPrecompile", "Tables", "Unicode", "WeakRefStrings", "WorkerUtilities"]
git-tree-sha1 = "c700cce799b51c9045473de751e9319bdd1c6e94"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.9"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "9c209fb7536406834aa938fb149964b985de6c83"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.1"

[[deps.Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "00a2cccc7f098ff3b66806862d275ca3db9e6e5a"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.5.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.0.1+0"

[[deps.CompositionsBase]]
git-tree-sha1 = "455419f7e328a1a2493cabc6428d79e951349769"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.1"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "fb21ddd70a051d882a1686a5a550990bbe371a95"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.4.1"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "e8119c1a33d267e16108be441a287a6981ba1630"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.14.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SnoopPrecompile", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "d4f69885afa5e6149d0cab3818491565cf41446d"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.4.4"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.DataValues]]
deps = ["DataValueInterfaces", "Dates"]
git-tree-sha1 = "d88a19299eba280a6d062e135a43f00323ae70bf"
uuid = "e7dc6d0d-1eca-5fa6-8ad6-5aecde8b7ea5"
version = "0.4.13"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DefineSingletons]]
git-tree-sha1 = "0fba8b706d0178b4dc7fd44a96a92382c9065c2c"
uuid = "244e2a9f-e319-4986-a169-4d1fe445cd52"
version = "0.1.2"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "7be5f99f7d15578798f338f5433b6c432ea8037b"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.16.0"

[[deps.FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "e27c4ebe80e8699540f2d6c805cc12203b614f12"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.20"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "37e4657cd56b11abe3d10cd4a1ec5fbdb4180263"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.7.4"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InitialValues]]
git-tree-sha1 = "4da0f88e9a39111c2fa3add390ab15f3a44f3ca3"
uuid = "22cec73e-a1b8-11e9-2c92-598750a2cf9c"
version = "0.3.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InvertedIndices]]
git-tree-sha1 = "82aec7a3dd64f4d9584659dc0b62ef7db2ef3e19"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.2.0"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JSONSchema]]
deps = ["HTTP", "JSON", "URIs"]
git-tree-sha1 = "8d928db71efdc942f10e751564e6bbea1e600dfe"
uuid = "7d188eb4-7ad8-530c-ae41-71a32a6d4692"
version = "1.0.1"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "cedb76b37bc5a6c702ade66be44f831fa23c681e"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.0.0"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "42324d08725e200c23d4dfb549e0d5d89dede2d2"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.10"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.0+0"

[[deps.MicroCollections]]
deps = ["BangBang", "InitialValues", "Setfield"]
git-tree-sha1 = "4d5917a26ca33c66c8e5ca3247bd163624d35493"
uuid = "128add7d-3638-4c79-886c-908ea0c25c34"
version = "0.1.3"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.2.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.NodeJS]]
deps = ["Pkg"]
git-tree-sha1 = "905224bbdd4b555c69bb964514cfa387616f0d3a"
uuid = "2bd173c7-0d6d-553b-b6af-13a54713934c"
version = "1.3.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.20+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "6503b77492fd7fcb9379bf73cd31035670e3c509"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.3.3"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6e9dba33f9f2c44e08a020b0caf6903be540004"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.19+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.Parsers]]
deps = ["Dates", "SnoopPrecompile"]
git-tree-sha1 = "8175fc2b118a3755113c8e68084dc1a9e63c61ee"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.5.3"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.8.0"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "LaTeXStrings", "Markdown", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "96f6db03ab535bdb901300f88335257b0018689d"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.2.2"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Referenceables]]
deps = ["Adapt"]
git-tree-sha1 = "e681d3bfa49cd46c3c161505caddf20f0e62aaa9"
uuid = "42d2dcc6-99eb-4e98-b66c-637b7d73030e"
version = "0.1.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "c02bd3c9c3fc8463d3591a62a378f90d2d8ab0f3"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.17"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SnoopPrecompile]]
deps = ["Preferences"]
git-tree-sha1 = "e760a70afdcd461cf01a575947738d359234665c"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.3"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "a4ada03f999bd01b3a25dcaa30b2d929fe537e00"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.1.0"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SplittablesBase]]
deps = ["Setfield", "Test"]
git-tree-sha1 = "e08a62abc517eb79667d0a29dc08a3b589516bb5"
uuid = "171d559e-b47b-412a-8079-5efa626c420e"
version = "0.1.15"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StringManipulation]]
git-tree-sha1 = "46da2434b41f41ac3594ee9816ce5541c6096123"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.0"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.0"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.TableTraitsUtils]]
deps = ["DataValues", "IteratorInterfaceExtensions", "Missings", "TableTraits"]
git-tree-sha1 = "78fecfe140d7abb480b53a44f3f85b6aa373c293"
uuid = "382cd787-c1b6-5bf2-a167-d5b971a19bda"
version = "1.0.2"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "c79322d36826aa2f4fd8ecfa96ddb47b174ac78d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.10.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.ThreadsX]]
deps = ["ArgCheck", "BangBang", "ConstructionBase", "InitialValues", "MicroCollections", "Referenceables", "Setfield", "SplittablesBase", "Transducers"]
git-tree-sha1 = "34e6bcf36b9ed5d56489600cf9f3c16843fa2aa2"
uuid = "ac1d9e8a-700a-412c-b207-f0111f4b6c0d"
version = "0.1.11"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "94f38103c984f89cf77c402f2a68dbd870f8165f"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.11"

[[deps.Transducers]]
deps = ["Adapt", "ArgCheck", "BangBang", "Baselet", "CompositionsBase", "DefineSingletons", "Distributed", "InitialValues", "Logging", "Markdown", "MicroCollections", "Requires", "Setfield", "SplittablesBase", "Tables"]
git-tree-sha1 = "c42fa452a60f022e9e087823b47e5a5f8adc53d5"
uuid = "28d57a85-8fef-5791-bfe6-a80928e7c999"
version = "0.4.75"

[[deps.URIParser]]
deps = ["Unicode"]
git-tree-sha1 = "53a9f49546b8d2dd2e688d216421d050c9a31d0d"
uuid = "30578b45-9adc-5946-b283-645ec420af67"
version = "0.4.1"

[[deps.URIs]]
git-tree-sha1 = "ac00576f90d8a259f2c9d823e91d1de3fd44d348"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.Vega]]
deps = ["DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "JSONSchema", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "Setfield", "TableTraits", "TableTraitsUtils", "URIParser"]
git-tree-sha1 = "c6bd0c396ce433dce24c4a64d5a5ab6dc8e40382"
uuid = "239c3e63-733f-47ad-beb7-a12fde22c578"
version = "2.3.1"

[[deps.VegaLite]]
deps = ["Base64", "DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "TableTraits", "TableTraitsUtils", "URIParser", "Vega"]
git-tree-sha1 = "3e23f28af36da21bfb4acef08b144f92ad205660"
uuid = "112f6efa-9a02-5b7d-90c0-432ed331239a"
version = "2.6.0"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[deps.WorkerUtilities]]
git-tree-sha1 = "cd1659ba0d57b71a464a29e64dbc67cfe83d54e7"
uuid = "76eceee3-57b5-4d4a-8e66-0e911cebbf60"
version = "1.6.1"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.12+3"

[[deps.ZygoteRules]]
deps = ["MacroTools"]
git-tree-sha1 = "8c1a8e4dfacb1fd631745552c8db35d0deb09ea0"
uuid = "700de1a5-db45-46bc-99cf-38207098b444"
version = "0.2.2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.1.1+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╟─526df6c0-92e6-40f9-96b8-8400e172c44a
# ╠═0f13e168-a1a3-11ed-1d08-6d1b9fd20152
# ╟─a5fb7e11-38ca-49a3-87a8-35afd5d8ed1b
# ╟─8624f4f9-a9f6-4938-ad73-a3e279eaa93b
# ╟─9362eaad-ff3e-437f-bd6e-5515a913641f
# ╠═3cb20b83-935e-4766-99d1-0d25a0becdce
# ╠═89cb4259-9724-4c12-a587-da43028c1750
# ╠═c91e5550-37b7-4cf9-b8b5-7aeb1957e524
# ╟─eddc27e9-fe8e-490e-b849-52e32dd7019d
# ╟─324fe9f0-b3f6-4345-98e8-2bf66e5fe893
# ╟─f5cbdb7a-b215-44ba-b01b-d4bae48ba106
# ╟─db8e7773-9ead-48ba-829a-2ef9b7710a1d
# ╠═d7c35096-e9d2-4881-9a55-783ecc49d612
# ╟─05a82650-9f18-4b77-b54c-3fd587e56522
# ╟─6aca02ac-0b48-4643-b18b-6b9f26677881
# ╟─510ae8dc-2288-4927-9552-782fc98dd290
# ╟─5a8890a3-6d0a-495a-b261-9b68933b95a2
# ╠═0ae085ec-ec13-4f26-b6f2-4bf7d264865f
# ╠═fbf2b366-b36e-4f2e-9ffb-2a2bedf9305a
# ╟─00ab4336-e085-4c18-b868-09986348205d
# ╟─6cb90013-5e91-435f-bfac-85eccb13d4f4
# ╟─570c59ec-31aa-475a-9284-eba9418ed2e6
# ╠═1c551031-d877-4327-9bcd-6380682ff190
# ╟─f8e20f63-eb07-48df-9fa1-617ab49697e7
# ╟─9fc66684-1f99-4d5f-8cce-c5c4899bfa8b
# ╟─4dba1e91-f86e-496e-a595-2710e7c5b93f
# ╟─a6c357d8-db82-4820-ac81-e650d787cf54
# ╠═6c80ce03-dd0d-4d4a-883e-8bfc34e71009
# ╠═54c1df98-0f66-4150-bc38-39ed1d9689e6
# ╟─b534f5eb-90ce-44ae-86ae-061e91c56bf4
# ╟─9c227e4f-5663-4423-84a9-1862458c591f
# ╠═af765635-304c-4688-a412-ff12a5554885
# ╟─27f2a510-9e43-4f56-8deb-144164cc9e1e
# ╟─a7ce54f2-ec66-43ab-823b-50834369bf3f
# ╟─abf0af13-6028-4ca7-8736-0947429639d2
# ╠═954ede07-53c7-4b64-bba4-4072c6e43863
# ╟─cf704ae2-8a2b-49ea-a1ac-23a60a9c3666
# ╟─1c321919-8ee2-4472-8979-66b7eb29f52d
# ╠═6458cb46-7e17-4b92-87fd-d09125db5498
# ╟─af68db74-0447-41cf-87a6-d8cdb8c0d82c
# ╟─860f4a45-8c8a-46b0-9bf3-fd505a34196e
# ╠═52d3fdd8-e078-45c8-9e81-9ee4bd6531e9
# ╟─5cc69e6a-4f9f-43fb-8cc7-f1062491de2e
# ╟─445285b9-643b-4f64-a9ea-6f97d5b009e2
# ╠═0367be00-5fc5-4973-bfd2-e042ba21714a
# ╟─505c2151-3a55-41ca-a1fa-d41ef97cde54
# ╠═f844f06a-0a53-481d-a642-7816224ec649
# ╟─0542e747-1bd7-4df1-918c-2a6be441ae34
# ╟─efd4108f-abc5-4b8f-b923-d63b351ed8b9
# ╟─764aec64-93fe-4253-923c-82b0c6ef7ab2
# ╠═27f02918-ab29-4df5-9c7a-e61997d1013b
# ╠═3f9287e3-a09c-4516-ac74-82da80ec6519
# ╠═d81b74eb-5014-481c-a0bc-979f5f6fb564
# ╟─031e7ec2-41ff-477e-a27e-f4548bbda7b9
# ╟─72749fd6-8cdb-450a-86e1-be55ea8688b5
# ╟─24781723-f438-4cfd-8163-5bdd1f39b6bc
# ╠═c54a6985-5262-456d-ae9a-e0fb13106d84
# ╟─3f45d54a-9d70-42c5-aa23-214d516023b4
# ╠═42672886-0154-4014-b69d-8f470d973c04
# ╟─660dc65d-42eb-477b-84f7-197d6b56c6ad
# ╠═4e8bf324-7d1d-4550-956a-1eb1d87c28c8
# ╟─e4f67c5c-dabc-4c78-a113-097d912e6a60
# ╠═54d11ae3-9272-4087-858b-1f7d18bd6fdd
# ╟─58b5cc2a-240a-4486-9fa7-8fc73b43f65c
# ╠═974eb941-73c6-41c3-881d-2b9ce4b5b950
# ╠═cfe4a08c-7b96-4ce0-920e-5d397c889c80
# ╟─68f57dcf-5c07-4249-9f52-4308f8e997a2
# ╠═bfe33c3d-7766-410d-8f74-4739fe498525
# ╟─4efd1e1e-a9da-45b9-bf70-7bb9b2c9aad9
# ╠═d683edf1-dd0e-424e-a32f-66c5baaad975
# ╠═8190950a-75dd-45cd-ae9b-28f3b29c4cdb
# ╟─e0022d18-4cbf-462d-8936-f187e5836432
# ╠═a711fbc9-40cc-4b57-997c-33f45d50fcba
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
