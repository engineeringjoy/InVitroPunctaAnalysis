#!/usr/bin/env python2
# -*- coding: utf-8 -*-
"""
PACC_PeakFinder_v4.py

v4 switchs order of identifying peaks. Previous version of the code was 
calculating the threshold off of the raw signal but this was the incorrect
approach since the background subtracted signal was the one being used
in find_peaks. Here:
    1. Calculate background
    2. Calculate raw neurite signal 
    3. Calculate background subtracted raw neurite signal
    4. Use signal from step 3 to calculate threshold according to this algo:
            1. Q3 is calculated for all pixel raw intensities
            2. A subset of pixels with intensity [0,Q3) is generated
            3. The mean and standard deviation is calculated for this new subset
            4. The threshold for peak intensity is then the mean+2*sigma. 
                => This value is very close to the std for the full population &
                guarantees an SNR of at least 1. 
    5. Feed these parameters into find_peaks

Also made some changes to how the indices for the neurite versus background 
were calculated. 

15MAR2020 - Changing Prominence to be calculated based off total population std
"""
#LIBRARIES
import os
import matplotlib.pyplot as plt
import pandas 
import glob
import datetime
import imageio
import numpy as np
from scipy.signal import find_peaks
from matplotlib import colors

# *** UPDATE NOTE TO STORE WITH ANALYSIS RUN ***
# Specify notes about this analysis run
rdmeNote = ["Green channel analysis"]
# Specify color to analyze (green = 1, red = 0)
CH = 1                                                                         # This numbering is defined by imageio.imread 
# Specify color file (green = 0, red =1 e.g., JN0 = analyze green channel images)                                             
chExt = 'JN0'


# *** GET TIME OF ANALYSIS START ***
toa = str(datetime.datetime.today()).split()                                   # Analysis runs are saved with unique timestamps
today = toa[0]
now = toa[1]
timestamp = today.replace('-','')+'-'+now.replace(':','')[:6]

# *** WHAT TO ANALYZE ***
prepID = 'CCP_127'                                                             # Cell-culture prep from where the NS arises
nsID = 'NS_02.01'                                                              # Neurite set (NS) to analyze  

#       ****       WHERE TO GET DATA & METADATA     ****
dirCCPs = "/Users/nerdette/Google Drive/Research/WormSense/Data/CCPs/"  # Location where data is stored for all preps   
dirPrep = dirCCPs+prepID+"/"                                                   # Location where all prep-specific data is stored      
dirMetaD = dirPrep+"Metadata/"                                                 # Directory for all prep-specific metadata  
dirNS = dirPrep+"Images/Cropped/"+nsID+"/"                                     # Directory for NS images to be analyzed (req'd for analysis)     
fnMDim = prepID+'.MetaD.IM.csv'                                                # Path to imaging metadata (req'd for analysis)  
fnMDns = prepID+".MetaD."+nsID+".csv"                                          # Name of NS metatadata file (req'd for analysis) 

#       ****        WHERE TO STORE RESULTS         ****
pathRes = dirPrep+"Analysis/"+timestamp+'/'
os.mkdir(pathRes)                                                  # Output locataion for final excel workbook                              
fnRes = 'PACC_PFAnalysis.'+prepID+'.'+nsID+'.'+timestamp+'.xlsx'               # Output Excel file 


#      ***   OUTPUT TEXT FILE TO DESCRIBE ANALYSIS RUN
os.chdir(pathRes)
rdmeFile = open(prepID+"_AnalysisRDME."+timestamp+".txt","w+") 
rdmeFile.writelines(rdmeNote) 
rdmeFile.close() #to change file access modes 


#       ***       IMPORT METADATA FOR ANALYSIS      ***
dfMDim = pandas.read_csv(dirMetaD+fnMDim)                                      # Import original imaging metadata
dfMDim.columns = dfMDim.columns.str.strip().str.lower().str.replace(' ', 
                 '_').str.replace('(', '').str.replace(')', '')
dfMDns = pandas.read_csv(dirMetaD+fnMDns)                                      # Import neurite set metadata
dfMDns.columns = dfMDns.columns.str.strip().str.lower().str.replace(' ', 
                 '_').str.replace('(', '').str.replace(')', '')

#       ***     COUNT EXCLUSION INSTANCES AND TYPES     ***
dfExclusions = dfMDns['exclusion_reason'].value_counts()                       # Poss entries are: None, Bipolar, Psuedo Bipolar, No neurites, other 

#       ***         GET LIST OF IMAGES TO ANALYZE       ***                                                
os.chdir(dirNS)
ims = glob.glob('*.'+chExt+'.tif')                                             # chExt = JN0 for green, JN1 for red

# *** ANALYSIS PARAMETERS ***
f = os.path.basename(__file__)                                                 # Store filename of *.py analysis code
muperpx = dfMDim.loc[0,'calibration_um/pix']                                   # Get um/pix conversion factor from metadata


# *** CALCULATE PIXELS TO SAMPLE ***
pxTot = dfMDns.loc[0,'line_width']
pxBgndSize = (pxTot/4)
pxNeuSize = int(round(1/muperpx))
pxNeuStart = (pxTot-pxNeuSize)/2
# Only preliminary data was acquired at lower resolution. All images used 
# for official analysis should be taken at muperpx == .126. 
# Analysis for .252 case is for backwards compatability. 
if muperpx == .252:    
    #calc indices for pixels to sample in image
    inB1 = 0                                                                       #Getting pixel indices  
    inB2 = pxBgndSize-1
    inN1 = pxNeuStart
    inN2 = pxNeuStart+pxNeuSize-1
    inB3 = pxTot-pxBgndSize                                                   
    inB4 = pxTot-1                                                                 #Pixel index is size-1 
elif muperpx == .126:
    #calc indices for pixels to sample in image
    inB1 = 0                                                                       #Getting pixel indices  
    inB2 = pxBgndSize-1
    inN1 = pxNeuStart             
    inN2 = pxNeuStart+pxNeuSize-1
    inB3 = pxTot-pxBgndSize
    inB4 = pxTot-1

pxN = [inN1,inN2]                                                              #Pixel range for neurite   
pxB = [inB1,inB2,inB3,inB4]      
                                            #Pixel range for background 
dfPixInd = pandas.DataFrame(np.array([['background_1',inB1, inB2],
                                     ['neurite',inN1,inN2],
                                     ['background_2',inB3,inB4]]),
                            columns = ['region','index_start','index_end'])

#           *** SETUP DATAFRAMES TO SAVE AS SPREADSHEETS IN ***
#           ***     EXCEL FILE AT THE END OF ANALYSIS       ***
#General data about each image column
colsData =     ['date','image_id','prep_id','strain','ns_id',
                'tiv','pattern_geom','surface_proteins',
                'distance','normalized_distance',
                'raw_intensity','background_intensity','neurite_intensity',
                'avg_norm_neu_int','max_norm_neu_int']

#Info about peaks found in image
colsPeaks =    ['date','image_id','prep_id','strain','ns_id',
                'tiv','pattern_geom','surface_proteins',
                'distance','normalized_distance',
                'punctum_max_intensity','norm_punctum_max_int','punctum_width']

#Info on inter-puncta distances
colsIPDs =     ['date','image_id','prep_id','strain','ns_id',
                'tiv','pattern_geom','surface_proteins',
                'distance','normalized_distance',
                'inter-punctum_interval']

#Calculated info about image, peaks, and IPDs
colsAnalysis = ['date','image_id','prep_id','strain','ns_id',
                'tiv','pattern_geom','surface_proteins',
                'image_size','max_neurite_length','average_neurite_intensity',
                'total_peaks','average_peaks_per_micron',
                'average_peak_intensity', 'average_peak_width',
                'average_ipd','median_ipd',
                'qTh','ss_mean','ss_median','ss_std','ss_n',
                'min_height','prominence']

#Track pixels used for each region of analysis
colsPixRange = ['region','starting_index','final_index']                       

#***initialize dataframes***
dfData = pandas.DataFrame()                                                       
dfPeaks = pandas.DataFrame()
dfIPDs = pandas.DataFrame()
dfAnalysis = pandas.DataFrame()


# *** MAIN PEAK FINDER ANALYSIS LOOP ***
os.chdir(dirNS) 

for x in ims:      
    # fileIm is the name of the original, regional image as it's called in the
    #   MetaD.IM.csv file
    fileIm = x.split(".C")[0]
    
    # Import image and store it in a list of lists
    img = imageio.imread(x)[:,:,CH]                                            #CH should be an integer to specify which color images to analyze (1 = GRN, 0 = RED)
    
    # Find index of fileIm in MetaD.IM.csv dataframe
    # Returns '0' if the file doesn't exist
    chk4file = dfMDim[dfMDim['image_name']==fileIm].index                      
    
    # Throw error if the image isn't found
    if(chk4file.size == 0):
        print("Error. Image file " +fileIm+ " is not in the original", 
              " metadata sheet & will not be included in analysis.")
    # If image does exist, proceed with metadata gathering & data analysis
    else:
        # ADD IMPORTANT METADATA TO MEASUREMENTS
        # Use index to get relavent metadata from MetaD.IM.csv dataframe
        index = chk4file[0]
        date = dfMDim.at[index,'acquisition_date']                             
        strain = dfMDim.at[index,'strain']
        tiv = dfMDim.at[index,'tiv']
        pattern_geom = dfMDim.at[index,'pattern_geom']
        surface_proteins = dfMDim.at[index,'surface_proteins']
        
        # ADD IMAGE DATA TO DATA FRAME
        # Calculate image size                                  
        imsize = np.shape(img)
        #***setup horizontal axes to represent image columns**
        d=np.arange(imsize[1])                                                 #Array of integers to represent pixels along image (aka image columns)
        dist = d*muperpx                                                       #Generate array of physical distances along image based on um:pix conversion factor
        normdist=dist/dist[-1]                                                 #Create a normalized axis to represent positions along image as 0->1 
        #***break image up into background and neurite***
        n = img[pxN[0]:pxN[1], 0:]                                             #Extract neurite rows
        bg = np.concatenate((img[pxB[0]:pxB[1], 0:],                           #Extract background rows 
                             img[pxB[2]:pxB[3], 0:]))   
        #***calculate values for analysis***
        rawf = np.mean(n, axis=0)                                              #Average raw neurite fluorescence
        bgf = np.mean(bg, axis=0)                                              #Average raw background fluorescence
        nf = rawf - bgf                                                        #Background subtracted neurite fluorescence
        annf= nf/np.mean(nf,axis=0)                                            #Average normalized neurite fluorescencece 
        mnnf = nf/np.amax(nf,axis=0)
        #***set negative nf values to zero
        for i in range(len(nf)):
            if nf[i]<0: nf[i]=0
        #***add image data dataframme***
        alldata1 = pandas.DataFrame({'date':[date]*imsize[1], 
                                     'image_id':[x]*imsize[1], 
                                     'prep_id':[prepID]*imsize[1],
                                     'strain':[strain]*imsize[1],
                                     'ns_id':[nsID]*imsize[1],
                                     'tiv':[tiv]*imsize[1],
                                     'pattern_geom':[pattern_geom]*imsize[1],
                                     'surface_proteins':[surface_proteins]*imsize[1],
                                     'distance':dist,
                                     'normalized_distance':normdist,
                                     'raw_intensity':rawf, 
                                     'background_intensity':bgf, 
                                     'neurite_intensity':nf,
                                     'avg_norm_neu_int':annf,
                                     'max_norm_neu_int':mnnf}, columns=colsData)
        dfData=dfData.append(alldata1)
        
        
        # DETERMINE PEAK LOCATIONS
        # Calculate minimum height and prominence values
        # 1. Calculate Third Quartile for all image neurite pixels rawf values
        descNF= alldata1['neurite_intensity'].describe()
        qTh = descNF[['75%']][0]
        # 2. Create a subset of pixels that are below the third quartile
        dfSS_alldata1 = alldata1[alldata1['neurite_intensity'] < qTh] 
        # 3. Calculate important stats for this subset
        descSS = dfSS_alldata1['neurite_intensity'].describe()
        mean = descSS[['mean']][0]    
        median = descSS[['50%']][0]
        stdSS = descSS[['std']][0]
        n = descSS[['count']][0]
        # 4. Use these statistics to calcualte cutoff values
        minHeight = mean+2*stdSS
        #prom = 2*std
        # 5. Use pop std to calculate prominence cutoff values
        descNI = alldata1['neurite_intensity'].describe()                          
        prom = descNI[['std']][0]
        
        
        #***find peaks***
        peaks = find_peaks(nf, height=minHeight, prominence=prom,              #Relheight is used to calculate peak width, it is a % of peak prominence 
                           width=0, rel_height=0.5)
        pd = peaks[0]*muperpx                                                  #Convert pixel distances to physical distances 
        pnd = pd/dist[-1]                                                      #Calculated normalized physical distances (0->1) 
        pmi = [nf[i] for i in peaks[0]]                                        #Get intensity for each punctum location                                   
        pmi_norm = [mnnf[i] for i in peaks[0]]                                 #Get max normalized intensity for each punctum location 
        #***calculate punctum spacing***
        ipd = np.diff(pd)                                                      #Here, .diff() returns physical distance between puncta                                                  
        ipdd = [pd[i]+ipd[i]/2 for i in range(0,len(ipd))]                     #Inter-punctum interval:   
        ipdnd = ipdd/dist[-1]
        #***add peak data to dataframe***
        alldata2 = pandas.DataFrame({'date':[date]*len(pd), 
                                     'image_id':[x]*len(pd), 
                                     'prep_id':[prepID]*len(pd),
                                     'strain':[strain]*len(pd),
                                     'ns_id':[nsID]*len(pd),
                                     'tiv':[tiv]*len(pd),
                                     'pattern_geom':[pattern_geom]*len(pd),
                                     'surface_proteins':[surface_proteins]*len(pd),
                                     'distance':pd,
                                     'normalized_distance':pnd,
                                     'punctum_max_intensity':pmi,
                                     'norm_punctum_max_int':pmi_norm,
                                     'punctum_width':peaks[1]['widths']*muperpx}, 
                                     columns=colsPeaks)
        dfPeaks=dfPeaks.append(alldata2)
        #***add Inter-punctum data to dataframe***
        alldata3 = pandas.DataFrame({'date':[date]*len(ipd), 
                                     'image_id':[x]*len(ipd), 
                                     'prep_id':[prepID]*len(ipd),
                                     'strain':[strain]*len(ipd),
                                     'ns_id':[nsID]*len(ipd),
                                     'tiv':[tiv]*len(ipd),
                                     'pattern_geom':[pattern_geom]*len(ipd),
                                     'surface_proteins':[surface_proteins]*len(ipd),
                                     'distance':ipdd, 
                                     'normalized_distance':ipdnd, 
                                     'inter-punctum_interval':ipd}, 
                                     columns=colsIPDs)
        dfIPDs=dfIPDs.append(alldata3)    
        
        #***add analysis to dataframe***
        # calculated info about image, peaks, and IPDs
        frame = pandas.DataFrame([[date, x, prepID, strain, nsID, tiv,         # 'Date','ImageID','Prep ID','Strain','NS ID','tiv' 
                                   pattern_geom, surface_proteins,             # 'pattern_geom','surface_proteins', 
                                   imsize[1], dist[-1], np.mean(nf),           # 'Image size','Max neurite length','Average neurite intensity'
                                   len(pd), len(pd)/dist[-1],                  # 'Total peaks', 'Average Peaks per Micron'                                    
                                   np.mean(pmi),                               # 'Average peak intensity'
                                   np.mean(peaks[1]['widths']*muperpx),        # 'Average peak width'
                                   np.mean(ipd), np.median(ipd),
                                   qTh,mean,median,stdSS,n,minHeight,prom]],             # 'Average ipd','Median ipd'
                                   columns=colsAnalysis)
        dfAnalysis = dfAnalysis.append(frame)
        
        #   ***     Create image specific analysis file    ****
        
        # Set main figure properties
        SMALL_SIZE = 4
        MEDIUM_SIZE = 6
        BIGGER_SIZE = 8
        plt.style.use('dark_background')
        plt.rc('font', size=MEDIUM_SIZE)          # controls default text sizes
        plt.rc('axes', titlesize=MEDIUM_SIZE)     # fontsize of the axes title
        plt.rc('axes', labelsize=MEDIUM_SIZE)    # fontsize of the x and y labels
        plt.rc('xtick', labelsize=SMALL_SIZE)    # fontsize of the tick labels
        plt.rc('ytick', labelsize=SMALL_SIZE)    # fontsize of the tick labels
        plt.rc('legend', fontsize=SMALL_SIZE)    # legend fontsize
        plt.rc('figure', titlesize=BIGGER_SIZE)  # fontsize of the figure title
        fig, axes = plt.subplots(3, 2, dpi=300,figsize=(6.5,4.5))
        ((ax1, ax2),(ax3,ax4),(ax5,ax6)) = axes
        fig.suptitle(x+'\nAnalysis '+timestamp+'\nProminence = '+str(round(prom,2))+' Min Height = '+str(round(minHeight)))
        plt.subplots_adjust(top = 0.99, bottom=0.01, hspace=.5, wspace=0.4)
    
        # Plot #1 is the raw image
        ax1 = plt.subplot(311)                                                  #subplot(nrows, ncols, index, **kwargs)
        ax1.set_title('Raw Image')
        # Shift the plot down so that it doesn't overlap with the title
        box = ax1.get_position()
        box.y0 = box.y0 - 0.1
        box.y1 = box.y1 - 0.1
        ax1.set_position(box)
        ax1.set_ylim((0,pxTot)) 
        ax1.set_yticks((pxBgndSize/2,pxTot/2,pxTot-(pxBgndSize/2)))
        labels = ['Background','Neurite','Background']
        ax1.yaxis.set_ticklabels(labels,position=(0,.05))
        ax1.set_xlabel('Pixel Index')
        ax1.hlines((inB2,inN1,inN2,inB3),0,imsize[1],color='w', linewidth =.2,linestyles= 'dashed')
        ax1.imshow(img, vmin=0,vmax=180)
        
        # Plot #2 is the histogram of pixel intensities
        ax3 = plt.subplot(323)
        ax3.set_title('Distribution of Pixel Intensities')
        ax3.set_xlabel('Pixel Intensity (AU)')
        ax3.set_ylabel('Pixel Count')
        n_bins = 25
        N, bins, patches = ax3.hist(nf, bins=n_bins)
        ax3.set_ylim((0,N.max()*1.1))
        p1 = plt.vlines(qTh, 0, N.max()*1.1, color='w',linewidth=.25)
        p2 = plt.vlines(minHeight, 0, N.max()*1.1, color='m',linewidth=.25)
        p3 = plt.vlines(prom, 0, N.max()*1.1, color='b',linewidth=.25)
        # N is the count in each bin, bins is the lower-limit of the bin
        # We'll color code by height, but you could use any scalar
        fracs = N / N.max()
        # we need to normalize the data to 0..1 for the full range of the colormap
        norm = colors.Normalize(fracs.min(), fracs.max())
        # Now, we'll loop through our objects and set the color of each accordingly
        for thisfrac, thispatch in zip(fracs, patches):
            color = plt.cm.viridis(norm(thisfrac))
            thispatch.set_facecolor(color)
        plt.legend((p1,p2,p3), 
                   ('Third Quartile', 'Minimum Height','Prominence'),  loc='upper right', bbox_to_anchor=(1,1))    
        
        # Plot #3 is the raw background and neurite signal
        ax4 = plt.subplot(324)
        ax4.set_title('Mean Pixel Intensity for Region of Interest')
        ax4.set_xlabel('Distance (um)')
        ax4.set_ylabel('Intensity (AU)')
        ax4.set_xlim(0,max(dist))
        ax4.set_ylim(0,max(rawf)*1.1)
        plt.yticks([0,round((max(rawf)*1.1)/2,-1),round((max(rawf)*1.1),-1)])
        p4 = plt.plot(dist, bgf, 'c-')
        p5 = plt.plot(dist, rawf, 'g-')
        plt.legend((p4[0], p5[0]), 
                   ('Background', 'Neurite'),  loc='best', bbox_to_anchor=(1,1))
        
        #Plot #4 is the corrected neurite signal with identified peaks
        ax5 = plt.subplot(313)
        ax5.set_title('Identified Peaks')
        plt.xlabel('Distance (um)')
        plt.ylabel('Intensity (AU)')
        ax5.set_ylim(0,max(nf)*1.1)
        ax5.set_xlim(0,max(dist))
        plt.yticks([0,round((max(nf)*1.1)/2,-1),round((max(nf)*1.1),-1)])
        p6 = plt.plot(dist, np.array([minHeight for i in xrange(len(dist))]), 'm-')
        p7 = plt.plot(dist, nf, 'b-')
        p8 = plt.plot(pd, pmi, 'mo',markersize=4)
        plt.legend((p6[0],p7[0], p8[0]), ('Minimum Height', 
                    'Corrected Neurite Signal', 'Identified Peak'), 
                    loc='upper right', bbox_to_anchor=(1,1))
        
        plt.savefig(pathRes+x[:-4]+'_pf.png',  bbox_inches='tight', 
                    dpi = 300,  
                    format = "png")
               
        plt.close()
  
    #END ANALYSIS#    

#***store user-specified and analysis parameters***
dfParameters = pandas.DataFrame(data={'1. Date of analysis':today, 
                                       '2. Time of analysis':now, 
                                       '3. Microns per pixel':muperpx, 
                                       '4. Script name':f}, 
                                        index=[0])
                              
#OUTPUT DATAFRAMES AS SHEETS IN EXCEL FILE
wb = pandas.ExcelWriter(pathRes+fnRes, engine='xlsxwriter')
dfData.to_excel(wb, sheet_name='Data')
dfPeaks.to_excel(wb, sheet_name='Peaks')
dfIPDs.to_excel(wb, sheet_name='IPDs')
dfAnalysis.to_excel(wb, sheet_name='Analysis')
dfExclusions.to_excel(wb, sheet_name='Exclusions')
dfPixInd.to_excel(wb,sheet_name='Pixel Indices')
dfParameters.to_excel(wb, sheet_name='Parameters')
wb.save()




















