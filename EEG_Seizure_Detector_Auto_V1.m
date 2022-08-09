% Coded on July 1, 2021
% Last updated on August 2, 2022
% Coded by Kyle J. Jackson - University of Iowa - Carver College of Medicine

% Start of Code - This block set the file path and locates folders in the file chain ------------------------------------

start_path = fullfile('EEG Analysis Code');
topLevelFolder = uigetdir(start_path);
allSubFolders = genpath(topLevelFolder);
remain = allSubFolders;
listOfFolderNames = {};

while true
	[singleSubFolder, remain] = strtok(remain, ';');
	if isempty(singleSubFolder)
		break;
	end
	listOfFolderNames = [listOfFolderNames singleSubFolder];
end

numberOfFolders = length(listOfFolderNames);
set(0,'DefaultFigureVisible','off')             %Change 'off' to 'on' if you want plotted figures to show, also refer to the last line of code (313)


% This block of code is where data collecting and processing begins ---------------------------------------
for k = 1 : numberOfFolders
	thisFolder = listOfFolderNames{k};                                      % This specifies the current folder for searching
	fprintf('Processing folder %s', thisFolder);    
    filePattern = sprintf('%s/*.edf', thisFolder);                          % This obtains the names of EDF files in the current folder
	baseFileNames = dir(filePattern);                                       % This saves the name of EDF files in the current folder
    numberOfEDFFiles = length(baseFileNames);                               % This counts the number of EDF files present
    
    Summary_Names = {zeros(numberOfEDFFiles,1)};                            % Saves the mouse number for export to excel
    Summary_Data = zeros(numberOfEDFFiles,3);                               % Saves the mouse spikes/seizures for export to excel
    
    if numberOfEDFFiles >= 1                                                %This loop scans through all the EDF files and extracts data
		for f = 1:numberOfEDFFiles
			fullFileName = fullfile(thisFolder, baseFileNames(f).name);
			fprintf('\nProcessing EDF file %s \n \n', fullFileName);
            Mouse_Number = erase(baseFileNames(f).name, '.edf');            % This saves the mouse number (e.g. S20, S21, etc.)
            Data = edfread(baseFileNames(f).name,'TimeOutputType','datetime');  % This is where EDF data is brought into matlab
            Data.Properties.DimensionNames = ["DateTime" "Variables"];  	% Converts EDF data to dd/mm/yyyy - hh/mm/ss format
            info = edfinfo(baseFileNames(f).name);                         	% Saves parameters for the EDF file
            Record = 1;                                                  	% EEG Record
            Lead = 1;                                                       % EEG Lead/Electrode
            Voltage_V = vertcat(Data.EEG{:});
            Time_total = info.NumDataRecords*info.DataRecordDuration;    	% Total of data points in the EEG trace
            Time_seg = Time_total/length(Voltage_V);                    	% Converts frequency to time in seconds
            Voltage_mV = Voltage_V * 1000;                              	% Converts EEG voltage values from volts to mV
            ABS_Voltage_mV = abs(Voltage_mV);                               % Finds the absolute value of EDF data

            
% This block of code AUTOMATICALLY determines the baseline, lower threshold, and upper threshold values
            Start_Value = 100;                                              %uV
            Tally = 0;                                                      %Placeholder variable   
            Percent = 0;                                                    %Placeholder variable
            while Percent < 0.97 && Start_Value <= 130                      % 0.97 = the set percentage of data points that MUST be below threshold value
                for a = 1:2000000                                           % Scan window for determing lower threshold (1 step = 0.002 seconds)
                    if ABS_Voltage_mV(a) < Start_Value/1000                 % Logic loop for determining threshold 
                        Tally = Tally + 1;                                  % Not relevant
                    else
                    end
                end
                Start_Value = Start_Value + 5;                              % Increases the lower threshold by 5 uV each pass through the loop
                Percent = Tally/a;                                          % Current percentage of data points that are below the threhsold value
                Tally = 0;                                                  % Not relevant
            end
            
            fprintf('The baseline EEG value was set at %.0f µV \n', Start_Value-5)
            Baseline = Start_Value-5;                                       % This is the baseline value in uV
            Lower_Threshold = 2*Baseline;                                   % This is the lower threshold in uV (2X the baseline)
                        
            Upper_Threshold = 1500;                                         % This is the upper threshold, set at 1500 uV
            Lower_Threshold_Adj = Lower_Threshold*0.001;                    % This converts the lower threshold to mV
            Upper_Threshold_Adj = Upper_Threshold*0.001;                    % This converts the upper threshold to mV
            
% Date and Time Conversion --------------------------------------------------------------------
            Start_Date = Data.DateTime(1,1);                                % Start date and time for EEG trace
            End_Date = Data.DateTime(end,1);                                % End date and time for EEG trace
            DateTime_Vector = linspace(Start_Date,End_Date,length(Voltage_mV)); % Creates array of date/time variables
            Timeframe = round(hours(End_Date-Start_Date),1);                % Rounds length of EEG trace to nearest 0.1 hours
            Timeframe_String = num2str(Timeframe);                          % Converts length of EEG trace to a string variable
            
% Peak Finding Algorithm ----------------------------------------------------------------------
            [spikes,position,width,prom] = findpeaks(ABS_Voltage_mV,'MinPeakDistance',50, 'MinPeakProminence', 0.2, 'MinPeakHeight', Lower_Threshold_Adj, 'MaxPeakWidth', 100);      % Finds positive EEG spikes
            peaks = zeros(1,length(spikes));                                % This variable contains all the peak amplitudes
            location = zeros(1,length(spikes));                             % This variable contains all the peak locations in seconds
            DateTime = zeros(1,length(spikes));                             % This variable contains the date and time associated with each peak
            
            for i = 1:length(spikes)
                if spikes(i) > 2*Baseline/1000 && spikes(i) < Upper_Threshold_Adj   % Determines if peak is > threshold
                    peaks(1,i) = spikes(i);                                 % Saves peak amplitudes as new variable
                    location(1,i) = position(i);                            % Saves peak locations (seconds) as new variable
                    DateTime(1,i) = datenum(DateTime_Vector(1,position(i)));% Saves date/time for each peak
                else
                    peaks(1,i) = 0;                                         % Disregards peaks < 2X baseline or > 1500 uV
                    location(1,i) = 0;                                      % Disregards location of peaks that dont satisfy above criteria
                    DateTime(1,i) = datenum(DateTime_Vector(1,position(i))); % Saves date and time of false peaks
                end
            end      
            
            peaks_2 = zeros(1,length(peaks));                               % Placeholder variable
            location_2 = zeros(1,length(location));                         % Placeholder variable
            spike_count = 0;                                                % Placeholder variable
            for p = 1:length(peaks)                                         % Logic loop that converts to positive AND negative values
                if peaks(1,p) > 0                                           % Peaks with a value > 0 are saved
                    peaks_2(1,p) = Voltage_mV(position(p));                 % Saves true peak amplitude (mV) with negative values present
                    location_2(1,p) = location(p);                          % Saves true peak location 
                    spike_count = spike_count + 1;                          % Counts the number of true peaks
                else
                end
            end
            
            % Remove false peaks from "peaks_4" variable
            peaks_3 = transpose(peaks_2);                                   % Transposes peaks_2 array
            location_2 = transpose(location_2);                             % Transposes location_2 array
            DateTime = transpose(DateTime);                                 % Transposes DateTime array
            aa = size(peaks_3,1);                                           % Placeholder Variable
            bb = true(aa,1);                                                % Logic Statement placeholder variable
            for cc=1:aa
                if peaks_3(cc,1) ~= 0                                       % Removes false peaks
                    bb(cc,1) = false;                                       % Logic statement 
                end
            end
            peaks_3(bb,:) = [];                                             % Rewrites variable with ONLY TRUE PEAKS
            location_2(bb,:) = [];                                          % Rewrites variable with ONLY TRUE PEAK LOCATIONS
            DateTime(bb,:) = [];                                            % Rewrites variable with ONLY TRUE PEAK DATES AND TIMES
                       
%Reorganize Data for Hourly Counts ----------------------------------------------------------------
            location_2 = location_2*0.002;                                  % Converts location to seconds
            Peak_Data = [DateTime location_2 peaks_3];                      % Creats a matrix of date/time, position (s), and amplitude for ALL TRUE peaks
            
            % Count peaks by the hour -------------------------------------------------------------
            time_array = datetime(Peak_Data(:,1),'ConvertFrom','datenum');  % Converts datenum to datetime
            time_array = datetime(time_array,'I','MM-dd-uuuu HH:mm:SS');    % Converts datetime to MM-DD-YYYY-HH-MM-SS format
            [Y,M,D,H] = datevec(time_array);                                % Saves Y,M,D,H,M,S as separate variables
            [b,~,ii] = unique([Y,M,D,H],'rows');                            % Saves Y,M,D,H,M,S as one string
            T_out = table(datetime([b,zeros(size(b,1),2)],'f','MM-dd-uuuu HH:00'),accumarray(ii,1),'v',{'Dates','# of Spikes'});    % Creates table of spikes by hour
            filename = strcat(Mouse_Number,' EEG Spike and Seizure Data by Hour.xlsx');     % Generates the name of the excel file using mouse number
            writetable(T_out,filename,'Sheet',1,'Range','B2')               % Exports data and creates excel file with seizure data
            
            % Clean up data for Seizure Detection --------------------------------------------------
            v = size(Peak_Data,1);                                      % Placeholder Variable
            d = false(v,1);                                             % Logic Statement placeholder variable
            for u=1:v
                if Peak_Data(u,3) < 3*Baseline/1000                     % Removes peaks less than 3X baseline value 
                    d(u) = true;                                        % Logic statement 
                end
            end
            Peak_Data(d,:) = [];                                        % Saves new Peak_Data variable with peaks 3X baseline or greater
                       
% Seizure Detector -----------------------------------------------------------------------------
            Interval = zeros(2,length(Peak_Data));                      % Placeholder Variable
            Int_Length = length(Peak_Data(:,1));                        % Determines length of Peak_Data variable
            for q = 1:Int_Length-1                                      
                Interval(1,q) = Peak_Data(q+1,2) - Peak_Data(q,2);      % Calculates distance between spikes
                Interval(2,q) = Peak_Data(q,2);                         % Saves location (s) of spikes
            end
            
            Status = zeros(2,length(Interval));                         % Placeholder variable
            for r = 1:length(Interval)
                if Interval(1,r) > 5                                    % Loop exlcudes spikes more than 5 seconds apart from being part of the same seizure
                    Status(1,r) = 0;                                    % If true (> 5 seconds apart), the iterating spike chain breaks
                    Status(2,r) = Interval(2,r);                        % Variable that saves the legnth of time between spikes
                else
                    Status(1,r) = 1;                                    % If false (< 5 seconds apart), the spike chain continues to iterate
                    Status(2,r) = Interval(2,r);                        % Variable that saved the length of time between spikes
                end
            end
            
            Seizure_Record = zeros(length(Status),5);                   % Placeholder variable
            Spike_Tally = 0;                                            % Placeholder variable
            Seizure_Length = 0;                                         % Placeholder variable
           
            for s = 1:length(Status)     
                if Status(1,s) == 1                                     % If the spikes are less than 5 seconds apart, the loop continues
                    Spike_Tally = Spike_Tally + 1;                      % Counts the number of spikes in each seizure
                    Seizure_Length = Seizure_Length + Interval(1,s);    % Records the growing length of the seizure
                else                                                    % If spikes are greater than 5 seconds apart, the loop breaks
                    Spike_Tally = Spike_Tally + 1;                      % Memory variable. DO NOT CHANGE!
                    Seizure_Record(s,1) = Spike_Tally;                  % Saves the number of spikes in the last seizure
                    Seizure_Record(s,2) = Seizure_Length;               % Saves the length of the last seizure
                    Seizure_Record(s,3) = Interval(2,s-Spike_Tally+1);  % Saves the beginning location of the seizure
                    Seizure_Record(s,4) = Seizure_Record(s,2) + Seizure_Record(s,3);% Saves the ending location of the seizure
                    Seizure_Record(s,5) = Peak_Data(s,1);               % Saves the date and time associated with the beginning of the seizure
                    Spike_Tally = 0;                                    % Resets the spike counter to 0 for the next seizure
                    Seizure_Length = 0;                                 % Resets the seizure length to 0 for the next seizure
                end
            end
            
            w = size(Seizure_Record,1);                                 % Determines the number of seizures saved
            x = false(w,1);                                             % Logic statement placeholder variable
            for y=1:w
                if Seizure_Record(y,2) == 0                             % Removes single spikes that aren't part of a seizure
                    x(y) = true;                                        % Logic statement for removing false seizures
                end
            end
            Seizure_Record(x,:) = [];                                   % Saves Seizure_Record variable with single spikes removed
            
            g = size(Seizure_Record,1);                                 % Determines the number of seizures saved
            h = true(g,1);                                              % Logic statement placeholder variable
            for z=1:g                                                   % Loop removes seizures with duration less than 10 seconds
                if Seizure_Record(z,2) > 10                             % '10' = minimum seizure length in seconds
                    h(z) = false;                                       % Logic statement for above loop
                end
            end
            Seizure_Record(h,:) = [];                                   % Saves Seizure_Record variable with ONLY TRUE seizures
                
                
% Plotting EEG Data - Seconds Time Scale -----------------------------------------------------------------------
            Time = transpose(0:Time_seg:Time_total);                    % Creates a time variable in seconds
            figure                                                      % Creates a new figure window
            plot(seconds(Time(1:end-1)),Voltage_mV,'k-')                % Plots RAW EEG data trace in seconds time scale
            hold on
            plot(location_2,peaks_3,'ro')                               % Plots red circles that mark detected peaks
            leg = legend(strcat("Record ",int2str(Record),", Lead ",int2str(Record)," ",info.SignalLabels(Lead)));  % Creates a legend on the figure
            set(leg,'AutoUpdate','off')                                 % Adjusts legned for proper display
            xlim([0 250])                                               % Sets X-axis window from 0 to 250 seconds
            ylim([-1.5 1.5])                                            % Sets Y-axis window from -1.5 to 1.5 mV
            xlabel('Time (s)')                                          % Creates X-axis label 
            ylabel('Voltage (mV)')                                      % Creates Y-axis label
            title(strcat(Timeframe_String,"-", 'Hour EEG Data for Mouse'," ", Mouse_Number,' - Seconds Time Scale'))    % Creates a title for the figure
            
            for t = 1:length(Seizure_Record(:,1))                       % Loop that plots seizure bars on the figure
                plot([Seizure_Record(t,3) Seizure_Record(t,4)],[1.0 1.0], 'r', 'LineWidth', 4)  % Plots red bars above true seizures on the plot
            end
            yline(Lower_Threshold/1000, 'r-')                           % Creates a red line at the lower threshold value (positive)
            yline(-Lower_Threshold/1000, 'r-')                          % Creates a red line at the lower threshold value (negative)
            yline(Baseline/1000, 'b-')                                  % Creates a blue line at the baseline value (positive)
            yline(-Baseline/1000, 'b-')                                 % Creates a blue line at the baseline value (negative)
           
            Panning = pan;                                              % Enables panning on the figure
            Panning.Motion = 'horizontal';                              % Fixes panning to the X-axis only
            Panning.Enable = 'on';                                      % Turns on fixed horinotal panning
            hold off
            
            % Unsuppress the next two lines of code if you want figures to generate and save automatically as MATLAB .fig files 
            %figurename = (strcat(Mouse_Number," ",'EEG Peaks and Seizures - Seconds.fig'));
            %savefig(figurename)
            
% Plotting EEG Data - Minutes Time Sacle ---------------------------------------------------------------------
            Time2 = minutes(Time);                                      % Creates a time variable in minutes
            figure                                                      % Creates a new figure window
            plot(Time2(1:end-1),Voltage_mV, 'k-')                       % Plots RAW EEG data trace in minutes time scale
            hold on
            plot(location_2/60,peaks_3,'ro')                            % Plots red circles that mark detected peaks
            xlim([0 60])                                                % Sets X-axis window from 0 to 60 minutes
            ylim([-1.5 1.5])                                            % Sets Y-axis window from -1.5 to 1.5 mV
            xlabel('Time (minutes)')                                    % Creates X-axis label
            ylabel('Voltage (mV)')                                      % Creates Y-axis label
            title(strcat(Timeframe_String,"-", 'Hour EEG Data for Mouse'," ", Mouse_Number,' - Minutes Time Scale'))    % Creates a title for the figure
            
            for t = 1:length(Seizure_Record(:,1))                       % Loop that plots seizure bars on the figure
                plot([Seizure_Record(t,3)/60 Seizure_Record(t,4)/60],[1.0 1.0], 'r', 'LineWidth', 4)    % Plots red bars above true seizures on the plot
            end
            yline(Lower_Threshold/1000, 'r-')                           % Creates a red line at the lower threshold value (positive)
            yline(-Lower_Threshold/1000, 'r-')                          % Creates a red line at the lower threshold value (negative)
            yline(Baseline/1000, 'b-')                                  % Creates a blue line at the baseline value (positive)
            yline(-Baseline/1000, 'b-')                                 % Creates a blue line at the baseline value (negative)
            
            Panning = pan;                                              % Enables panning on the figure
            Panning.Motion = 'horizontal';                              % Fixes panning to the X-axis only
            Panning.Enable = 'on';                                      % Turns on fixed horizontal panning
            hold off
            
            % Unsuppress the next two lines of code if you want figures to generate and save automatically 
            %figurename = (strcat(Mouse_Number," ",'EEG Peaks and Seizures - Minutes.fig'));
            %savefig(figurename)
                      
%Export Seizure Data to Excel --------------------------------------------------------------------
            filename = strcat(Mouse_Number,' EEG Seizure Data.xlsx');   % Generates the name of the excel file using mouse number
            varNames = {'Date','Start Time (mins)','End Time (mins)','# of Spikes in Seizure','Duration (s)'}; % Saves names for variables on excel sheet
            Date_Time_3 = datetime(Seizure_Record(:,5),'ConvertFrom','datenum');  % Converts from datenum to datetime format
            T_pos = table(Date_Time_3,Seizure_Record(:,3)/60,Seizure_Record(:,4)/60,Seizure_Record(:,1),Seizure_Record(:,2),'VariableNames',varNames);  % Creates a table of data for excel
            writetable(T_pos,filename,'Sheet',1,'Range','B2')           % Exports data and creates excel file with seizure data
                       
% Seizure Counts and Output -----------------------------------------------------------------------
            seizure_count = length(Seizure_Record(:,1));                % Counts the number of true seizures
            fprintf('\nThe total number of EEG spikes is %0.f during the EEG trace\n', spike_count) % Outputs number of spikes to Command Window
            fprintf('The total number of seizures is %0.f during the EEG trace\n', seizure_count)   % Outputs number of seizures to Command Window
            fprintf('\nEEG analysis complete. \nSeizure data exported to excel\n')    % Tells user that the EEG data has been analyzed
            fprintf('-----------------------------------------------------------------------------------------------------------')
            
            Summary_Names(f,1) = {Mouse_Number};                        % Array of all mice analyzed (S20, S21, S22, etc.)
            Summary_Data(f,1) = spike_count;                            % Saves the number of spikes for each mouse analyzed
            Summary_Data(f,2) = seizure_count;                          % Saves the number of seizures for each mouse analyzed
            Summary_Data(f,3) = Lower_Threshold;                        % Saves the lower threshold value determined for each mouse
            
            % Seizure Count by Hour Export to Excel
            warning('off', 'MATLAB:xlswrite:AddSheet')                  % Turns off an unnecessary warning message from MATLAB
    
            time_array2 = datetime(Date_Time_3,'I','MM-dd-uuuu HH:mm:SS');  % Converts Date/Time to MM-dd-yyyy HH-mm-ss format
            [Y2,M2,D2,H2] = datevec(time_array2);                       % Saves M,D,Y,H,M,S as separate variables
            [c,~,jj] = unique([Y2,M2,D2,H2],'rows');                    % Combines M,D,Y,H,M,S into on variable
            T_out_2 = table(datetime([c,zeros(size(c,1),2)],'f','MM-dd-uuuu HH:00'),accumarray(jj,1),'v',{'Dates','# of Seizures'}); % Creates table of seizures by hour
            filename = strcat(Mouse_Number,' EEG Spike and Seizure Data by Hour.xlsx');     % Creates the name of the excel file using mouse number
            writetable(T_out_2,filename,'Sheet',2,'Range','B2')         % Exports data and creates excel file with seizure data by hour
        end
    else
		fprintf('\nFolder %s has no EDF files in it.\n', thisFolder);
    end
    
    fprintf('\n')
        
    varNames_summary = {'Mouse','Spikes','Seizures','Lower Threshold (µV)'};    % Creates variable names for summary excel sheet
    Summary_Table = table(Summary_Names,Summary_Data(:,1),Summary_Data(:,2),Summary_Data(:,3),'VariableNames',varNames_summary); % Generates a table of summary information
    filename2 = strcat('EEG Data Summary Sheet.xlsx');                          % Creates a filename for the excel summary sheet
    writetable(Summary_Table,filename2,'Sheet',1,'Range','B2')                  % Exports and saves excel summary sheet
    %disp(Summary_Table) % Displays summary data to the screen
    
    clear                                                                       % Clears the Worksapce variables for next mouse to be analyzed
    clc                                                                         % Clears the Command Window for next mouse to be analyzed
    delete(findall(0));                                                         % Deletes all figures from MEMORY, even if they dont show
        % Suppress the previous line (313) if you want figures to show, also refer to line 22
end