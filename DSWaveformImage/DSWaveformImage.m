//
//  DSWaveformImage.m
//  soundcard
//
//  Created by Dennis Schmidt on 07.09.13.
//  Copyright (c) 2013 Dennis Schmidt. All rights reserved.
//

#import "DSWaveformImage.h"

@implementation DSWaveformImage {
  DSWaveformStyle _style;
}

- (id)initWithStyle:(DSWaveformStyle)style {
  self = [super init];
  if (self) {
    _graphColor = [UIColor whiteColor];
    _style = style;
  }

  return self;
}

+ (UIImage *)waveformForAssetAtURL:(NSURL *)url
							 color:(UIColor *)color
							height:(CGFloat)height
				   secondsPerPixel:(NSTimeInterval)secondsPerPixel
							 scale:(CGFloat)scale
							 style:(DSWaveformStyle)style {

	DSWaveformImage *waveformImage = [[DSWaveformImage alloc] initWithStyle:style];
	
	waveformImage.graphColor = color;
	secondsPerPixel *= scale;
	height *= scale;
	NSData *imageData = [waveformImage renderPNGAudioPictogramLogForURL:url withHeight:height andSecondsPerPixel:secondsPerPixel];
	
	UIImage *image = [UIImage imageWithData:imageData scale:scale];
	
	return image;
}

- (void)fillContext:(CGContextRef)context withRect:(CGRect)rect withColor:(UIColor *)color {
  CGContextSetFillColorWithColor(context, color.CGColor);
  CGContextSetAlpha(context, 1.0);
  CGContextFillRect(context, rect);
}

- (void)fillBackgroundInContext:(CGContextRef)context withColor:(UIColor *)backgroundColor size:(CGSize)imageSize {
  CGRect rect = CGRectZero;
  rect.size = imageSize;

  [self fillContext:context withRect:(CGRect) rect withColor:backgroundColor];
}

- (void)drawGraph:(Float32 *)samples
	  sampleCount:(UInt32)sampleCount
		withStyle:(DSWaveformStyle)style
		   inRect:(CGRect)rect
		onContext:(CGContextRef)context
		withColor:(CGColorRef)graphColor {

  float graphCenter = rect.size.height / 2;
  float sampleAdjustmentFactor = rect.size.height / 2;
  switch (style) {
    case DSWaveformStyleStripes:
      for (NSInteger intSample = 0; intSample < sampleCount; intSample++) {
        Float32 sampleValue = (Float32) *samples++;
        float pixels = sampleValue * sampleAdjustmentFactor;
        float amplitudeUp = graphCenter - pixels;
        float amplitudeDown = graphCenter + pixels;

        if (intSample % 5 != 0) continue;
        CGContextMoveToPoint(context, intSample, amplitudeUp);
        CGContextAddLineToPoint(context, intSample, amplitudeDown);
        CGContextSetStrokeColorWithColor(context, graphColor);
        CGContextStrokePath(context);
      }
      break;

    case DSWaveformStyleFull:
      for (NSInteger pointX = 0; pointX < sampleCount; pointX++) {
        Float32 sampleValue = (Float32) *samples++;

        float pixels = sampleValue * sampleAdjustmentFactor;
        float amplitudeUp = graphCenter - pixels;
        float amplitudeDown = graphCenter + pixels;

        CGContextMoveToPoint(context, pointX, amplitudeUp);
        CGContextAddLineToPoint(context, pointX, amplitudeDown);
        CGContextSetStrokeColorWithColor(context, graphColor);
        CGContextStrokePath(context);
      }
      break;

    default:
      break;
  }
}

- (UIImage *)audioImageLogGraph:(Float32 *)samples
                    sampleCount:(NSInteger)sampleCount
                    imageHeight:(float)imageHeight {

  CGFloat imageWidth = (CGFloat) sampleCount;
	
  CGSize imageSize = CGSizeMake(imageWidth, imageHeight);
	
	UIGraphicsBeginImageContext(imageSize);
  CGContextRef context = UIGraphicsGetCurrentContext();

  [self fillBackgroundInContext:context withColor:[UIColor clearColor] size:CGSizeMake(imageWidth, imageHeight)];

  CGColorRef graphColor = self.graphColor.CGColor;
  CGContextSetLineWidth(context, 1.0);
  CGRect graphRect = CGRectMake(0, 0, imageWidth, imageHeight);

  [self drawGraph:samples sampleCount:sampleCount withStyle:self.style inRect:graphRect onContext:context withColor:graphColor];

  // Create new image
  UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();

  // Tidy up
  UIGraphicsEndImageContext();

  return newImage;
}

- (NSData *)renderPNGAudioPictogramLogForURL:(NSURL *)url withHeight:(CGFloat)height andSecondsPerPixel:(NSTimeInterval) secondsPerPixel {

	
	OSStatus ret = noErr;
	
	ExtAudioFileRef extAudioFile;
	
	// Open the audio file
	CFURLRef cfURL = (__bridge CFURLRef _Nonnull)(url);
	
	ret = ExtAudioFileOpenURL(cfURL, &extAudioFile);
	
	if (ret != noErr) {
		
		return nil;
	}
	
	// Set the LPCM format that we are to read
	AudioStreamBasicDescription asbd = {

		44100.0, //Float64 mSampleRate;
		kAudioFormatLinearPCM, //AudioFormatID mFormatID;
		kAudioFormatFlagsNativeFloatPacked, //AudioFormatFlags mFormatFlags;
		8, //UInt32 mBytesPerPacket;
		1, //UInt32 mFramesPerPacket;
		8, //UInt32 mBytesPerFrame;
		2, //UInt32 mChannelsPerFrame;
		32, //UInt32 mBitsPerChannel;
		0 //UInt32 mReserved;
	};
	
	ret = ExtAudioFileSetProperty(extAudioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &asbd);
	
	if (ret != noErr) {
		
		return nil;
	}
	
	UInt32 framesPerPixel = secondsPerPixel * asbd.mSampleRate;
	
	// Configure a single buffer that hold framesPerPixel frames,
	// we will use to loop through the audio file
	UInt32 bufferSize = framesPerPixel * sizeof(Float32) * asbd.mChannelsPerFrame;
	Float32 *frames = malloc(bufferSize);
	
	AudioBuffer buffer = {
		2, // UInt32 mNumberChannels;
		bufferSize,// UInt32 mDataByteSize;
		frames// void* __nullable mData;
	};
	
	AudioBufferList abl = {
		1, //UInt32      mNumberBuffers;
		buffer//AudioBuffer mBuffers[1];
	};
	
	// Create the data buffer to hold waveform data points
	NSMutableData *waveFormData = [[NSMutableData alloc] init];
	
	// Initialize values for waveform normalization
	Float32 normalizeMax = 0;
	Float64 totalAmplitude = 0;
	
	// Read the audio and calculate data points for each pixel in the wave form
	UInt32 framesRead = 0;
	while(true) {
		
		framesRead = framesPerPixel;
		ret = ExtAudioFileRead(extAudioFile, &framesRead, &abl);
		
		if (ret == kAudioFileEndOfFileError || framesRead < framesPerPixel) {
		
			break;
		}
		if (ret != noErr) {
			
			assert(@"Failed to set audio client format");
			return nil;
		}
		
		int i = 0;
		while(i < framesRead) {
			
			// Get the highest amplitude of either channel
			Float32 amplitude = MAX(fabs(frames[i]),fabs(frames[i + 1]));
			
			totalAmplitude += amplitude;
			i+=2;
		}
		
		Float32 medianAmplitude = totalAmplitude / framesPerPixel;
		if (fabsf(medianAmplitude) > fabsf(normalizeMax)) {
			normalizeMax = fabsf(medianAmplitude);
		}
		
		[waveFormData appendBytes:&medianAmplitude length:sizeof(medianAmplitude)];
		totalAmplitude = 0;
	}
	
	int sampleCount = waveFormData.length / sizeof(Float32);
	
	[self normalize:waveFormData.mutableBytes
		 numSamples:sampleCount
				max:normalizeMax];
	
    UIImage *graphImage = [self audioImageLogGraph:(Float32 *) waveFormData.bytes
                                       sampleCount:sampleCount
                                       imageHeight:height];

    NSData *finalData = UIImagePNGRepresentation(graphImage);

	return finalData;
}

- (void) normalize:(Float32 *)samples numSamples:(UInt32)numSamples max:(Float32)max {
	
	if (max == 0)
		return;
	
	for(UInt32 i = 0; i < numSamples; i++) {
	
		if (samples[i] == 0)
			continue;
		
		samples[i] = 1.0 / (max / samples[i]);
	}
}
@end
