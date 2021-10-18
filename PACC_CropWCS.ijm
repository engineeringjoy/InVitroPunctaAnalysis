
/*
 * PACC_CropWCS.ijm
 * JFRANCO
 * 20210301
 * 
 * This macro is for cropping images of single cells to generate a "Whole Cell Set" (WCS) from 
 * larger images that are of entire fields of view at 60x. Due to the small size of the cells, 
 * the field of view is much larger than one cell and often contains multiple cells and debris. 
 * Cropping individual cells improves the results of the automated neurite tracing step. 
 * 
 * Updates as of 20210301 are aimed at correcting for a chromatic shift before cropping the images. 
 * The correction will apply a transformation to the CH2 images (red) so that they are aligned
 * to the CH3 images (green). 
 * 
 * Code functionality verified: 20210622
 */



/* 
 ************************** MACRO PACC_CropWCS.ijm ******************************
 */



/*
 * 	ENTER USER SPECIFIC INFORMATION
 */
 // Requires user specific changes
dirCCPs = "/Users/nerdette/Google Drive/Research/WormSense/Data/CCPs/";		// Path to main data subdirectory 
channels = newArray("_CH3","_CH2", "_CH4");											// Channel names associated with raw tif files, order matters: GFP, RFP, BF 
// Close irrelevant images that might be open
run("Close All");																	
// Location for dialog boxes
x_d = 260;							// x position of dialog boxes
y_d = 125;							// y position of dialog boxes 
// Location for images
x_iw = 260;							// x position of image window
y_iw = 300; 						// y position of image window


/*	
 * GET PREP, IMAGING, SAMPLING, AND WCS INFORMATION FROM USER
 */
//Check that results table is open
updateResults();

// Create dialog box
Dialog.create("Prep to analyze");
Dialog.addString("Prep Number",'125');
Dialog.addString("Whole Cell Set",'04');
Dialog.addString("Binning", '1x1');
Dialog.addNumber("Micron-to-Pixel Calibration", 0.126);
Dialog.setLocation(x_d,y_d);
Dialog.show();
// Read in values from dialog box
prepID = "CCP_"+Dialog.getString();
wcsID = "WCS_"+Dialog.getString();
binning = Dialog.getString();
cal = Dialog.getNumber();



/*
 * USE PROVIDED INFORMATION TO GENERATE PREP/WCS SPECIFIC PATHS AND FILENAMES
 */

// Existing files 
dirPrep = dirCCPs+prepID+"/";														// CCP specific path
dirMetaD = dirPrep+"Metadata/";														// Path to metadata files
dirRF= dirPrep+"Images/RawFrames/"; 												// Raw images to be cropped
dirMon = dirPrep+"Images/Montages/";												// Repository for storing generated montages
fnMDim = prepID+".MetaD.IM.csv";
// Files to be made during setup if this is the first run for WCS
dirWCS = dirPrep+"Images/Cropped/"+wcsID+"/"; 										// Path to WCS_## storage location for images that are cropped but retain raw intensity values											
dirROIs = dirPrep+"Locations/ROIs/"+wcsID+"/";										// Path to WCS_## storage location for ROIs identified during cropping
dirProc = dirPrep+"Images/Processed/"+wcsID+"/";									// Path to WCS_## storage location for cropped and processed representation images
fnMDwcs = prepID+".MetaD."+wcsID+".csv";


/*
 * CHECK IF CROPPING FOR THIS WCS HAS BEEN STARTED. 
 * & SETUP METADATA
 */
setupDir(dirWCS, dirProc, dirROIs, dirRF, dirMetaD, fnMDwcs);


/*
 * BEGIN CROPPING PROCESS
 */
choice = getUserChoice();
index = 0;
while (choice != 'EXIT') {
	// Start the analysis clock
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hourSt, minuteSt, secondSt, msecSt);
	strDateTime = getTimeStamp();

	// Get index of what image to open next
	index = findIndex(index);												// Fx uses index to iterate through ResultsTable and returns first instance where wcs_processed=NO
	imname = getResultString("image_name", index);
	
	// Set date and time of analysis
	timestamp = getTimeStamp();
	setResult("timestamp", index, timestamp);
	
	// Open unprocessed image & adjust for display
	fnIM_GFP = imname+channels[0]+".tif"; 
	pathToIm = dirRF+imname+"/";
	open(pathToIm+fnIM_GFP);
	setLocation(x_iw, y_iw);
	run("Invert");
	run("Enhance Contrast...", "saturated=0.1");

	// Verify if cropping should proceed
	options = Array.concat("YES", "NO");
	Dialog.create("PROCEED WITH CROPPING CHECK");
	Dialog.addChoice("Continue to image cropping?", options);
	Dialog.setLocation(x_d,y_d);
	Dialog.show();
	check = Dialog.getChoice();

	// Case where user wants to proceed with cropping
	if (check == 'YES'){
		// Threshold image 
		fixThresh = procToBinary(fnIM_GFP);
		setResult("fix_threshold", index, fixThresh);
		updateResults();
		// Get ROIs of neurons
		fixROIs = getROIs(fnIM_GFP, pathToIm, dirROIs);
		roicount = roiManager("count");
		// Taking a maximum of 5 neurons per image
		if (roicount>5) {
			roicount=5;
		}
		setResult("add_rois", index, fixROIs);
		updateResults();

		/*
		 * ITERATE THROUGH ROIs TO CROP IMAGES
		 */
		for (i = 0; i < roicount; i++) {
			/*
			 * Make a processed jpg of mNG image for review & display purposes
			 */
			open(pathToIm+fnIM_GFP);
			setLocation(x_iw, y_iw);
			run("Set Scale...", "distance=1 known="+cal+" pixel=1 unit=um global");
			setMinAndMax(0, 50);
			run("Invert");
			roiManager("Select", i);
			run("To Bounding Box");
			run("Enlarge...", "enlarge=25 pixel");
			run("Crop");
			fnProc = imname+".C"+toString(i)+".pp.jpg"; 
			// Rotate image to get cell body on left side
			autoRot = rotateImage(fnIM_GFP);
			// Check with user if rotation needs to be fixed
			userRot = fixRotate(fnIM_GFP);
			// Update Results Table to track work
			setResult("ar_c"+toString(i),index,autoRot);
			setResult("ur_c"+toString(i),index,userRot);
			updateResults();
			// Add scale bar and save image
			run("Scale Bar...", "width=5 height=4 font=20 color=White background=None location=[Lower Right] hide");
			saveAs("Jpeg",dirProc+fnProc);
			close();
			
			/*
			 * Make a set of cropped images for every channel with raw intensity values
			 */
			// Open raw .tif files for every channel
			for( j = 0; j < channels.length ; j++) {
				file = dirRF+imname+"/"+imname+channels[j]+".tif";
				open(file);
				run("Set Scale...", "distance=0.00 known=0.00 pixel=1 unit=pixel");
				// If this is the ch2 image it will need to be translated prior to stack formation
				if (j==1) {
					run("TransformJ Translate", "x-distance=1.5 y-distance=.5 z-distance=0.0 interpolation=Linear background=0.0");
					selectWindow(imname+channels[j]+".tif");
					close();
					selectWindow(imname+channels[j]+".tif translated");
					rename(imname+channels[j]+".tif");
				}
				setLocation(x_iw, y_iw);
			}
			//  Create image stack
			run("Images to Stack", "name=" + imname + " title=[] use");
			selectImage(imname);
			roiManager("Select", i);
			run("To Bounding Box");
			run("Enlarge...", "enlarge=25 pixel");
			run("Crop");
			// Rotate image to get cell body on left side
			run("Rotate 90 Degrees Right");
			if ((autoRot=="SKIP" && userRot=="FIX") || (autoRot=="ROT" && userRot=="SKIP")) {
				run("Rotate 90 Degrees Right");
				run("Rotate 90 Degrees Right");
			}
			// Save all images
			savename = imname+".C"+toString(i)+".WC"; 
			saveinfo = "["+dirWCS+"]";
			run("Image Sequence... ", "format=TIFF name="+savename+" digits=1 save="+saveinfo);
			selectImage(imname);
			close();
			}
		
		}else {
			// Case where user did not want to crop the image
			selectWindow(fnIM_GFP);
			close();
			setResult("fix_threshold", index, "NA");
			setResult("add_rois", index, "NA");
			updateResults();
		}

		// Stop the analysis clock and calculate duration
		getDateAndTime(year, month, dayOfWeek, dayOfMonth, hourFi, minuteFi, secondFi, msecFi);
		timeSt = (hourSt*3600) + (minuteSt*60) + secondSt + (msecSt/1000);
		timeFi = (hourFi*3600) + (minuteFi*60) + secondFi + (msecFi/1000);
		duration = timeFi-timeSt;
		setResult("duration", index, duration);
		updateResults();
		
		// Update wcs processed and update metadata file
		setResult("wcs_processed", index, 'YES');
		updateResults();
		selectWindow("Results");
		saveAs("Results", dirMetaD+fnMDwcs);

		/*
		 * Update index & user choice to continue cropping
		 */
		index++;
		if (index < nResults) {
			choice = getUserChoice();
		}else{
			waitForUser("All images have been cropped.\n"+
						"The macro will after montage generation.");
			choice = 'EXIT';
		}
		
}

/*			
 * Make montage of cropped images in WCS if user so chooses			
 */
options = Array.concat("NO", "YES");
Dialog.create("MAKE MONTAGE BEFORE EXITING?");
Dialog.addChoice("Proceed to montage generation?", options);
Dialog.addMessage("Montage will be made for all pp .jpgs\nin Processed folder");
Dialog.setLocation(x_d,y_d);
Dialog.show();
choiceMM = Dialog.getChoice();
if (choiceMM == "YES") {
	makeMontage(dirMon, dirProc, prepID, wcsID);
}

/*
 * ******************************	 MACRO END		******************************	
 */



/*
 * ************************	 	FUNCTION DEFINITIONS		**********************	
 */
function getTimeStamp(){
// 	FUNCTION GETS TIME STAMP FOR METADATA
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


function setupDir(dirWCS, dirProc, dirROIs, dirRF, dirMetaD, fnMDwcs){
// CHECKS IF CROPPING FOR THIS WCS HAS ALREADY BEEN STARTED
//     IF NO => Setup dirWCS, dirProc, dirROIs, and fnMDwcs
// 	   IF YES => Skip directory setup	
	if (File.exists(dirWCS)){
		// If the set exists, verify continuation
		Dialog.create("Error");
		Dialog.addCheckbox("WCS exists, continue? ",true);
		Dialog.setLocation(x_d,y_d);
		Dialog.show();
		inBoolean = Dialog.getCheckbox();
		if (!inBoolean){
			//If the user doesn't want to continue, get out 
			print("Note	Macro ended by user choice");
			exit("Note	Please restart & specify the correct WCS ID");
		}else {
			// If user wants to continue, load metadata
			setupMD(dirMetaD+fnMDwcs);
		}
	}else{
		// If WCS doesn't exist, initilize relevant items
		File.makeDirectory(dirWCS);
		File.makeDirectory(dirProc);
		File.makeDirectory(dirROIs);

		// Run FX for initializing results table for storing & generating metadata .csv file
		initResTable(dirRF, dirMetaD+fnMDwcs);
	}
}

function initResTable(dirRF, fPathMD){
// FUNCTION RUNS IF THIS IS THE FIRST TIME SETTING UP WCS. 
//    Fx setsup Results table with relevant column names

	// Setup MD Results Table based on list of images in RawFrames directory
	run("Clear Results");
	imlist = getFileList(dirRF); 
	for (i = 0; i < lengthOf(imlist); i++) {
		fn = substring(imlist[i], 0,lastIndexOf(imlist[i], '/'));
		setResult("image_name", i, fn);
		setResult("timestamp", i, 'TBD');
		setResult("wcs_processed", i, 'NO');
		setResult("duration", i, 'TBD');
		setResult("fix_threshold", i, 'TBD');
		setResult("add_rois",i,'TBD');
		for (j=0; j < 5; j++) {
			setResult("ar_c"+toString(j),i,'NA');
			setResult("ur_c"+toString(j),i,'NA');
		}
		updateResults();
	}

	// Immediately create a saved copy of the MD file
	selectWindow("Results");
	saveAs("Results", fPathMD);
}

function setupMD(fPath){
// FX Reads in csv file and setsup info as a Results table
//    In particular, reads in CCP_###.MetaD.WCS_##.csv
	run("Clear Results");
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
	Dialog.create("Puncta Analysis PreProcessing");
	Dialog.addChoice("To exit the cropping macro, select 'Exit", options);
	Dialog.setLocation(x_d,y_d);
	Dialog.show();
	
	// GET AND RETURN USER INPUT ONCE USER HITS 'OK' ON DIALOG BOX
	return Dialog.getChoice();
}

function findIndex(index) {	
	proc = getResultString("wcs_processed", index);
	while(proc == 'YES'){
		index++;
		if(index < nResults){
		proc = getResultString("wcs_processed", index);	
		}
		if(index >= nResults){
			exit("All images have been cropped. Macro will exit.\n"+
			"Restart and skip cropping to make montage");	
		}
	}
	return index;
}

function procToBinary(imname) {
	selectWindow(imname);
	run("Subtract Background...", "rolling=30 light separate sliding disable");
	run("Duplicate...", "title=Duplicate");
	selectWindow(imname);
	setOption("BlackBackground", false);
	run("Convert to Mask");
	run("Erode");
	run("Dilate");

	// Verify with user that thresholding is good and doesn't need adjustment
	choice = fixThreshold("Does thresholding need to be adjusted?");
	selectImage("Duplicate");
	close();
	return choice;
}

function fixThreshold(message){
// CHECK IF CURRENT THRESHOLDING IS SUFFICIENT OR IF USER NEEDS TO FIX IT
	optFix = Array.concat("SKIP","FIX");
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

function getROIs(imname, pathToIm, dirROIs) {
// ANALYZE PARTICLES TO REDUCE ROIs TO ONLY	THOSE THAT ARE NEURONS
	roiManager("reset");
	selectImage(imname);
	run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
	run("Analyze Particles...", "size=5000-Infinity circularity=0.00-0.20 solidity=0.00"+
	"display exclude add");	
	choiceAdd = addROIs(imname, pathToIm);
	if (roiManager("count")>0){
		roiManager("save", dirROIs+"/"+imname+".zip");
	}
	selectImage(imname);
	close();
	return choiceAdd;
}


function addROIs(imname , pathToIm ){
// CHECK IF THERE ARE ADDITIONAL ROIs that need to be added
	optAdd = Array.concat("SKIP","ADD");
	Dialog.create("ADD ROIs");
	Dialog.addMessage("Are there additional ROIs to identify?");
	Dialog.addChoice("Skip step or add new ROIs?", optAdd);	
	Dialog.setLocation(x_d,y_d);
	Dialog.show();
	choiceAdd = Dialog.getChoice();
	if (choiceAdd == "ADD") {
		open(pathToIm+imname );
		setLocation(x_iw, y_iw);
		run("Set Scale...", "distance=1 known="+cal+" pixel=1 unit=um global");
		run("Invert");
		run("Enhance Contrast...", "saturated=0.1");
		setTool("oval");
		waitForUser("Draw ovals around neurons to add, then press 't' to add to ROI manager.\n"+
					"Press ok when done."); 
		close();
	}
	return choiceAdd;
}

function rotateImage(imhandle){
// FUNCTION ATTEMPTS TO AUTOMATICALLY ROTATE THE IMAGE SO THAT THE CELL BODY
// IS ON THE LEFT SIDE OF THE IMAGE

	/*
	 * Attempt #1 to automate the image rotation process
	 */
	selectImage(imhandle);
	run("Rotate 90 Degrees Right");
	getDimensions(width, height, channels, slices, frames);
	widthNew = width/2;
	makeRectangle(0, 0, widthNew, height);
	lsFeretX = getValue("FeretX");
	makeRectangle(widthNew, 0, width, height);
	rsFeretX = getValue("FeretX");
	if (lsFeretX > rsFeretX){
		selectImage(imhandle);
		run("Rotate 90 Degrees Right");
		run("Rotate 90 Degrees Right");		
		return "ROT";
	}else{
		return "SKIP";
	}
}

function fixRotate(imhandle){
// FUNCTION CHECKS WITH USER IF IMAGE ROTATION NEEDS TO BE FIXED AND RETURNS RESPONSE	
	Dialog.create("ROTATION CHECK");
	Dialog.addMessage("The cell body should be on the left side with the\n"+
		"neurite extending to the right.");
	Dialog.addCheckbox("Repeat transformation?", false);
	Dialog.setLocation(x_d,y_d);
	Dialog.show();
	choiceRot = Dialog.getCheckbox();
	if (choiceRot) {
		// If rotation needs to be fixed, then it means image does not need
		// to be rotated beyond the original transformation
		run("Rotate 90 Degrees Right");
		run("Rotate 90 Degrees Right");
		return "FIX";
	}else{
		// If rotation doesn't need to be fixed, then the image did need to be 
		// rotated beyond the original transformation
		return "SKIP";
	}
}


function makeMontage(dirMon, dirProc, prepID, wcsID){
	fnMontage = prepID+".Montage.AllCropped."+wcsID+".jpg";
	imlist = getFileList(dirProc);
	for (i = 0; i < lengthOf(imlist); i++) {
		open(dirProc+imlist[i]);
		setLocation(x_iw, y_iw);
	}
	rows = round(lengthOf(imlist)/2);
	run("Images to Stack", "method=[Copy (center)] fnMontage title=[] use");
	run("Make Montage...", "columns=2 rows="+toString(rows)+" scale=0.50 label");
	saveAs("Jpeg",dirMon+fnMontage);
}




