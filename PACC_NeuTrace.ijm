/*
 * PACC_NeuTrace.ijm
 * JFRANCO
 * 20200812
 * 
 * This macro guides the user through the neurite tracing process. Many of the steps are automated but  
 */


/* 
 ************************** MACRO PACC_NeuTrace.ijm ******************************
 */
run("Close All");

/*
 * 	ENTER USER SPECIFIC INFORMATION
 */
 // Requires user specific changes
dirCCPs = "/Users/nerdette/Google Drive/Research/WormSense/MERLIN/Data/CCPs/";
channels = newArray("_CH3","_CH2", "_CH4");											// Channel names associated with raw tif files, order matters: GFP, RFP, BF 
// Close irrelevant images that might be open
run("Close All");																	
// Location for dialog boxes
x_d = 260;							// x position of dialog boxes
y_d = 125;							// y position of dialog boxes 
// Location for images
x_iw = 260;							// x position of image window
y_iw = 300; 						// y position of image window
// Location setup for ROI manager
x_roi = 0;
y_roi = 100;
run("ROI Manager...");
selectWindow("ROI Manager");
setLocation(x_roi, y_roi);

/*	
 * GET PREP, IMAGING, SAMPLING, AND WCS INFORMATION FROM USER
 */
// Create dialog box
Dialog.create("Prep to analyze");
Dialog.addString("Prep Number",'124');
Dialog.addString("Whole Cell Set",'01');
Dialog.addString("Neurite Set",'01');
Dialog.addString("Binning", '1x1');
Dialog.addNumber("Micron-to-Pixel Calibration", 0.126);
Dialog.addNumber("Physical Sampling Space (um)", 4);
Dialog.setLocation(x_d,y_d);
Dialog.show();
// Read in values from dialog box
prepID = "CCP_"+Dialog.getString();
wcs = Dialog.getString();
wcsID = "WCS_"+wcs;
nsID = "NS_"+wcs+"."+Dialog.getString();
binning = Dialog.getString();
cal = Dialog.getNumber();
samplespace = Dialog.getNumber();													// Physical sampling space 
linewidth = round(samplespace/cal);													// How thick of a line (in pixels) to draw around main trace line

/*
 * USE PROVIDED INFORMATION TO GENERATE PREP/WCS SPECIFIC PATHS AND FILENAMES
 */
 // Existing files 
dirPrep = dirCCPs+prepID+"/";														// CCP specific path
dirMetaD = dirPrep+"Metadata/";														// Path to metadata files
dirWCS = dirPrep+"Images/Cropped/"+wcsID+"/";										// Path to WCS files to use for tracing
dirProcWCS = dirPrep+"Images/Processed/"+wcsID+"/";									// Path to processed WCS files to use for display
dirMon = dirPrep+"Images/Montages/";												// Repository for storing generated montages
// Files to be made during setup if this is the first run for WCS
dirNS = dirPrep+"Images/Cropped/"+nsID+"/";															// Path to NS_## storage location for images that are traced but retain raw intensity values											
dirProcJN = dirPrep+"Images/Processed/"+nsID+"/";									// Path to NS_## storage location for traced and processed representation images
fnMDns = prepID+".MetaD."+nsID+".csv";												// File: Metadata for NS
	
/*
 * CHECK IF CROPPING FOR THIS WCS HAS BEEN STARTED. 
 * & SETUP METADATA
 */
setupDir(dirProcWCS, dirNS, dirProcJN, dirMetaD, fnMDns);

/*
 * BEGIN TRACING PROCESS
 */
choice = getUserChoice();
index = 0;
while (choice != 'EXIT') {
	// Start the analysis clock
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hourSt, minuteSt, secondSt, msecSt);
	strDateTime = getTimeStamp();
	// Get index of what image to open next
	index = findIndex(index);												// Fx uses index to iterate through ResultsTable and returns first instance where ns_processed=NO
	imname = getResultString("image_name", index);

	/* 
 	********   OPEN PROCESSED DISPLAY IMAGE TO TEST FOR INCLUSION  ***********
 	* Images are processed in the order they appear in imlist, therefore, indices should match up with what's in the 
	*	metadata and neurite tracing can be resumed using this approach
 	*/
	imnamePP = imname+".pp.jpg";
	open(dirProcWCS+imnamePP);
	setLocation(x_iw, y_iw);
	
	/* 
 	******** INCLUSION CHECK   ***********
 	*/
 	Dialog.create("Exlude TRN From Analysis?");
 	Dialog.setLocation(x_d,y_d);
	Dialog.addCheckbox("Exclude cell fron neurite set?", false);
	Dialog.addChoice("Exclusion Criteria:", newArray("Bipolar", "Psuedo-Bipolar", "No Neurites", "Other"));
	Dialog.show();
	exclude = Dialog.getCheckbox();
	reason = Dialog.getChoice();
	if(exclude){
		// CASE WHERE USER WANTS TO EXCLUDE CELL FROM NS
		inorout = "Exclude";
		selectWindow(imnamePP);
		fixes = newArray(4);
		fixes[0]=0;
		close();
	}else{
		// CASE WHERE USER WANTS TO INCLUDE CELL IN NS
		inorout = "Include";
		reason = "0";
		fixes = neuTrace(channels, imname, dirWCS, linewidth, cal, dirProcJN, dirNS, imnamePP);
	}
	
	/*
	 * STOP ANALYSIS CLOCK & CALCULATE PROCESSING TIME
	 */
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hourFi, minuteFi, secondFi, msecFi);
	timeSt = (hourSt*3600) + (minuteSt*60) + secondSt + (msecSt/1000);
	timeFi = (hourFi*3600) + (minuteFi*60) + secondFi + (msecFi/1000);
	duration = timeFi-timeSt;

	setResult("timestamp", index, strDateTime);
	setResult("ns_processed", index, 'YES');
	setResult("in_or_out",index,inorout);
	setResult("exclusion_reason",index,reason);
	setResult("duration", index, duration);
	setResult("cb_rois",index,fixes[0]);
	setResult("neu_rois",index,fixes[1]);
	cbFix = fixes[2];
	setResult("fix_cb",index,cbFix);
	neuFix = fixes[3];
	setResult("fix_neu",index,neuFix);
	updateResults();

	// Save results on each run in case macro crashes
	selectWindow("Results");
	saveAs("Results", dirMetaD+fnMDns);
	
	/*
	 * Update index & user choice to continue cropping
	 */
	index++;
	if (index < nResults) {
		choice = getUserChoice();
	}else{
		waitForUser("All images have been traced.\n"+
					"The macro will after montage generation.");
		choice = 'EXIT';
	}
}

/* 
********   MONTAGE GENERATION (IF APPLICABLE) *********** 
*/
options = Array.concat("NO", "YES");
Dialog.create("MAKE MONTAGE BEFORE EXITING?");
Dialog.setLocation(x_d,y_d);
Dialog.addChoice("Proceed to montage generation?", options);
Dialog.addMessage("Montage will be made for all pp .jpgs\nin Processed folder");
Dialog.show();
choiceMM = Dialog.getChoice();

if (choiceMM == "YES") {
	makeMontage(dirMon, dirProcJN, prepID, nsID);
}

exit("bye bye");
/*
 * ******************************	 MACRO END		******************************	
 */



/*
 * ************************	 	FUNCTION DEFINITIONS		**********************	
 */
function getTimeStamp(){
	print("\\Clear");
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	month++;
	if (month<10) {month = "0"+toString(month);}
	if (dayOfMonth<10) {month = "0"+toString(dayOfMonth);}
	date = toString(year)+ month + dayOfMonth;
	if (hour<10) {hour = "0"+toString(hour);}
	if (minute<10) {minute = "0"+toString(minute);}
	time = toString(hour)+"h"+toString(minute) +"m";
	arrDateTime = Array.concat(date + "_"+ time);
	Array.print(arrDateTime);
	strDateTime = toString(getInfo("log"));
	strDateTime = substring(strDateTime, 0, lengthOf(strDateTime)-1);
	return strDateTime;
}

// Make sure dirWCS exists and if not throw error, make dirNS, make dirProcJN, initialize results table for metaD and save; if ns has been started load metad
function setupDir(dirProcWCS, dirNS, dirProcJN, dirMetaD, fnMDns){
// VERIFIES THAT SPECIFIED WCS EXISTS; IF NOT => THROW ERROR
// CHECKS IF NEURITE TRACING HAS ALREADY BEEN STARTED
// 		IF NO => SETUP dirNS, dirProcJN, and fnMDns
// 		IF YES => LOAD fnMDns
	if(File.exists(dirWCS)==0){
		exit("Error; WCS does not exist. Please restart the macro and indicate a valid WCS.");
	}
	if (File.exists(dirNS)){
		// If the neurite set has already been started, verify continuation
		Dialog.create("NS EXISTS CHECK");
		Dialog.setLocation(x_d,y_d);
		Dialog.addCheckbox("NS exists, resume processing? ",true);
		Dialog.show();
		inBoolean = Dialog.getCheckbox();
		if (!inBoolean){
			// User does not want to resume processing, exit macro
			exit("Exit by user choice; Incorrect NS_ID");										
		}else {
			// User wants to resume processing, load metadata
			setupMD(dirMetaD+fnMDns); 												
		}
	}else{
		// If dirNS doesn't exist, initialize relevant items
		File.makeDirectory(dirNS);
		File.makeDirectory(dirProcJN);
		// Run FX for initializing results table for storing & generating metadata .csv file
		initResTable(dirProcWCS, dirMetaD+fnMDns);
	}	
}

function initResTable(dirProcWCS, fPathMD){
// FUNCTION RUNS IF THIS IS THE FIRST TIME SETTING UP NS. 
//    Fx setsup Results table with relevant column names

	// Setup MD Results Table based on list of images in ProcessedWCS directory
	run("Clear Results");
	imlist = getFileList(dirProcWCS);												 
	for (i = 0; i < lengthOf(imlist); i++) {
		fn = substring(imlist[i], 0, lastIndexOf(imlist[i], ".p"));
		setResult("image_name", i, fn);
		setResult("timestamp", i, 'TBD');
		setResult("ns_processed", i, 'NO');
		setResult("line_width", i, linewidth);
		setResult("in_or_out",i,'TBD');
		setResult("exclusion_reason",i,'TBD');
		setResult("duration", i, 'TBD');
		setResult("cb_rois",i,'TBD');
		setResult("neu_rois",i,'TBD');
		setResult("fix_cb",i,'TBD');
		setResult("fix_neu",i,'TBD');
		updateResults();
	}
	// Immediately create a saved copy of the MD file
	selectWindow("Results");
	saveAs("Results", fPathMD);
}

function setupMD(fPath){
// FX Reads in csv file and setsup info as a Results table
//    In particular, reads in CCP_###.MetaD.NS_##.##.csv
	lineseparator = "\n";
	cellseparator = ",\t";

	// copies the whole RT to an array of lines
	lines=split(File.openAsString(fPath), lineseparator);

	// recreates the columns headers
	labels=split(lines[0], cellseparator);
	if (labels[0]==" "){
		k=1; // it is an ImageJ Results table, skip first column
	}else{
	k=0; // it is not a Results table, load all columns
	}
	for (j=k; j<labels.length; j++)
		setResult(labels[j],0,0);
		// dispatches the data into the new RT
	run("Clear Results");
	for (i=1; i<lines.length; i++) {
		items=split(lines[i], cellseparator);
	for (j=k; j<items.length; j++)
   		setResult(labels[j],i-1,items[j]);
	}
	updateResults();
}

function getUserChoice() {
// SETUP GUI FOR USER TO EITHER QUIT OR SELECT NEXT IMAGE FOLDER
	options = Array.concat("CONTINUE", "EXIT");
	Dialog.create("NEURITE TRACING PROCESS");
	Dialog.setLocation(x_d,y_d);
	Dialog.addChoice("To exit the neurite tracing macro, select 'Exit", options);
	Dialog.show();
	
	// GET AND RETURN USER INPUT ONCE USER HITS 'OK' ON DIALOG BOX
	return Dialog.getChoice();
}

function findIndex(index) {	
	proc = getResultString("ns_processed", index);
	while(proc == 'YES'){
		index++;
		if(index < nResults){
		proc = getResultString("ns_processed", index);	
		}
		if(index >= nResults){
			exit("All images have been traced. Macro will exit.\n"+
			"Restart and skip tracing to make montage");	
		}
	}
	return index;
}

function neuTrace(channels, imnameBASE, dirWCS, linewidth, cal, dirProcJN, dirNS, imnamePP){
// FUNCTION TRACES NEURITE AND SAVES IMAGES	
	
	roiManager("reset");
	fixInfo = newArray(4);	
	// Open image & setup filenames for future purposes
	imnamesWC = newArray(3);
	imnamesJN = newArray(3);
	for (i = 0; i < lengthOf(channels); i++) {
		imnamesWC[i] = imnameBASE+".WC"+toString(i)+".tif";
		imnamesJN[i] = imnameBASE+".JN"+toString(i)+".tif";
	}
	open(dirWCS+imnamesWC[0]);
	setLocation(x_iw, y_iw);
	// Setup image to let user test if it should be included
	run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
	run("Invert");
	run("Enhance Contrast...", "saturated=0.1");
	run("Make Binary");
	run("Erode");
	run("Erode");
	
	// Check if user needs to fix anything
	message = "Fix threshold for cell body ID";
	fixCB = fixCheck(message);
	fixInfo[2] = fixCB;
	
	/*
	 *  ANALYZE  PARTICLES TO ID CELL BODY BLOB
	 *  Also verifies that correct ROI was identified and stores information about accuracy. 
	 */
	run("Analyze Particles...", "size=250-Infinity circularity=0.4-1.00 solidity=0.00"+
		 "exclude include add");
	fixInfo[0] = roiManager("count");															 // Count the number of blobs detected for cell body
	roiCB = fixInfo[0];
	if(roiCB < 1){
		waitForUser("CB not detected. Please draw and add to the ROI manager");
	}
	if(roiCB >1){
		waitForUser("Multiple CBs detected. Please delete wrong ROIs from the manager");
	}
	if(roiCB == 1){
		optCB = Array.concat("YES","NO");
		Dialog.create("Verify CB");
		Dialog.addMessage("CB detected. Please verify its accuracy before proceeding");
		Dialog.addChoice("Is CB detected correct?", optCB);
		Dialog.setLocation(x_d,y_d);	
		Dialog.show();
		choiceCB = Dialog.getChoice();
		if (choiceCB == 'NO') {
			roiCB=0;
			waitForUser("Please manually draw the correct ROI and add to ROI manager.");
		}
	}

	// Clean up
	selectWindow(imnamesWC[0]);
	close();

	// Open orginal image to preprocess for getting ROI for the neurite
	open(dirWCS+imnamesWC[0]);
	setLocation(x_iw, y_iw);
	run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
	roiManager("Select", 0);
	run("Enlarge...", "enlarge=5 pixel");
	getSelectionBounds(coord_x, coord_y, w_s, h_s);
	selectImage(imnamesWC[0]);
	getDimensions(w_i, h_i, chan, slices, frames);
	x_new = coord_x+w_s;
	w_new = w_i-x_new-1;
	makeRectangle(x_new, 0, w_new, h_i);
	roiManager("Add");
	run("Crop");
	// NOW THE CELL BODY ROI NEEDS TO BE DELETED FROM THE ROI MANAGER TO 
	//     HELP WITH HOUSEKEEPING
	roiManager("Select", 0);
	roiManager("delete");
	run("Select None");
	
	run("Invert");
	run("Enhance Contrast...", "saturated=0.1");
	run("Despeckle");
	run("Subtract Background...", "rolling=25 light separate sliding");
	run("8-bit");
	run("Auto Local Threshold", "method=Niblack radius=50 parameter_1=0 parameter_2=0");
	run("Invert");	
	run("Gaussian Blur...", "sigma=5");
	run("Make Binary");
	run("Erode");
	selectImage(imnamesWC[0]);
	run("In [+]");
	run("In [+]");
	run("Scale to Fit");
	selectWindow(imnamePP);
	setLocation(x_iw, y_iw+2*h_i);
	run("In [+]");
	run("In [+]");
	run("Scale to Fit");
	
	// Check if user needs to fix anything - this is where it would be good to have a 
	//    reference image available to the user to help them verify threshold
	message = "Fix threshold for neurite ID";
	fixNeu = fixCheck(message);
	fixInfo[3] = fixNeu;
	selectWindow(imnamePP);
	close();
	
	/*
	 * ANALYZE PARTICLES TO ID NEURITE & VERIFY ROI ACCURACY
	 */
	// Get ROI for neurite
	selectImage(imnamesWC[0]);
	run("Analyze Particles...", "size=1000-10000 circularity=0.00-0.5 solidity=0.00 AR=5-Infinity"+
		 "exclude include add");
	fixInfo[1] = roiManager("count");															 // Count the number of blobs detected for cell body
	roiNeu = fixInfo[1];															 // Count the number of blobs detected for cell body
	if(roiNeu < 2){
		waitForUser("Neurite not detected. Please draw and add to the ROI manager");
	}
	if(roiNeu >2){
		waitForUser("Multiple CBs detected. Please delete wrong ROIs from the manager");
	}
	if(roiNeu == 2){
		optNeu = Array.concat("YES","NO");
		Dialog.create("Verify Neurite ROI");
		Dialog.addMessage("Neurite detected. Please verify its accuracy before proceeding");
		Dialog.addChoice("Is the detected neurite blob correct?", optNeu);
		Dialog.setLocation(x_d,y_d);	
		Dialog.show();
		choiceNeu = Dialog.getChoice();
		if (choiceNeu == 'NO') {
			roiNeu=1;
			waitForUser("Please manually draw the correct ROI and add to ROI manager.");
		}
	}	

	// Use identified ROI to create a mask
	roiManager("Select", 1);
	run("Clear Outside");
	run("Create Mask");

	// Get LGCs from the mask
	run("Profile Plot Options...",											//Important to set options to get values from line graph
	     "list interpolate draw");
	run("Analyze Line Graph");
	Plot.getValues(xpoints, ypoints);
	close();
	selectWindow(imnamesWC[0]);
	close();
	selectWindow("Mask");
	close();
	
	// Make processed image of neurite for display purposes
	open(dirWCS+imnamesWC[0]);
	setLocation(x_iw, y_iw);
	run("Set Scale...", "distance=1 known="+cal+" pixel=1 unit=um global");
	// NEED TO CROP THE ORIGINAL IMAGE IN ORDER FOR THE COORDINATES OF THE NEURITE 
	//      SELECTION TO MAKE SENSE
	roiManager("select",0);
	run("Crop");
	run("Flip Vertically");
	run("Line Width...", "line="+linewidth);
	makeSelection( "polyline", xpoints, ypoints);
	waitForUser;
	run("Straighten...");
	selectWindow(imnamesWC[0]);
	close();
	setMinAndMax(0, 65);
	run("Subtract Background...", "rolling=30 separate sliding");
	run("Invert");
	width = getWidth();
	if (width < 500) {
		newwidth = 500;
	}else {
		newwidth = width;
	}
	run("Canvas Size...", "width="+width+" height=75 position=Top-Left");
	run("Scale Bar...", "width=5 height=4 font=20 color=White background=None location=[Lower Right] hide");
	fnProc = imnameBASE+".ppJN.jpg";
	saveAs("Jpeg",dirProcJN+fnProc);
	close();
	
	// Make raw but straightened views of neurite, substrate, and culture conditions
	//  Open images for all channels
	for( j = 0; j < channels.length ; j++) {
		file = dirWCS+imnamesWC[j];
		open(file);
	}
	run("Images to Stack", "name=stack" + " title=[] use");
	setLocation(x_iw, y_iw);
	run("Set Scale...", "distance=1 known="+cal+" pixel=1 unit=um global");
	// NEED TO CROP THE ORIGINAL IMAGE IN ORDER FOR THE COORDINATES OF THE NEURITE 
	//      SELECTION TO MAKE SENSE
	roiManager("select",0);
	run("Crop");
	
	run("Flip Vertically");
	makeSelection( "polyline", xpoints, ypoints);
	run("Fit Spline");
	run("Straighten...", "title=stack line="+linewidth+" process");

	fnCropped = imnameBASE+".JN";
	saveinfo = "["+dirNS+"]";
	run("Image Sequence... ", "format=TIFF name="+fnCropped+" digits=1 save="+saveinfo);
	run("Close All");
	
	//fixInfo = [roiCB, roiNeu, fixCellBody, fixNeu];	
	//fix1 = Array.concat(roiCB, roiNeu);
	//fix2 = Array.concat(fixCellBody,fixNeu);
	//fixInfo = Array.concat(array1,array2);
	return fixInfo;
	
}

function fixCheck(message){
// CHECK IF CURRENT THRESHOLDING IS SUFFICIENT OR IF USER NEEDS TO FIX IT
	optFix = Array.concat("FIX","SKIP");
	Dialog.create("FIX THRESHOLDING");
	Dialog.addMessage(message);
	Dialog.addChoice("Do you want to manually fix the IDd blobs?", optFix);
	Dialog.setLocation(x_d,y_d);	
	Dialog.show();
	choiceFix = Dialog.getChoice();
	if (choiceFix == "FIX") {
		setForegroundColor(255, 252, 255);
		setTool("Paintbrush Tool");
		waitForUser("Use white paintbrush to make cuts\n"+
			"then press enter.");
		setTool("Paintbrush Tool");
		setForegroundColor(0, 0, 0);
		waitForUser("Use black paintbrush to fill in gaps\n"+
			"then press enter."); 
	}
	return choiceFix;
}

function makeMontage(dirMon, dirProcJN, prepID, nsID){
	fnMontage = prepID+".Montage.AllCropped."+nsID+".jpg";
	imlist = getFileList(dirProcJN);
	for (i = 0; i < lengthOf(imlist); i++) {
		open(dirProcJN+imlist[i]);
	}
	rows = round(lengthOf(imlist)/2);
	run("Images to Stack", "method=[Copy (center)] fnMontage title=[] use");
	setLocation(x_iw, y_iw);
	run("Make Montage...", "columns=2 rows="+toString(rows)+" scale=0.50 label");
	saveAs("Jpeg",dirMon+fnMontage);
}
