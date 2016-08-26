//
//  DSWaveformImage.m
//  soundcard
//
//  Created by Dennis Schmidt on 07.09.13.
//  Copyright (c) 2013 Dennis Schmidt. All rights reserved.
//

#import "DSWaveformImage.h"

#define absX(x) (x<0?0-x:x)
#define minMaxX(x,mn,mx) (x<=mn?mn:(x>=mx?mx:x))
#define noiseFloor (-50.0)
#define decibel(amplitude) (20.0 * log10(absX(amplitude)/32767.0))

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
				   samplesPerPixel:(Float32)samplesPerPixel
							 scale:(CGFloat)scale
							 style:(DSWaveformStyle)style {

	DSWaveformImage *waveformImage = [[DSWaveformImage alloc] initWithStyle:style];
	
	waveformImage.graphColor = color;
	samplesPerPixel *= scale;
	height *= scale;
	NSData *imageData = [waveformImage renderPNGAudioPictogramLogForURL:url withHeight:height andFramesPerPixel:samplesPerPixel];
	
	return [UIImage imageWithData:imageData scale:scale];
}

- (void)fillContext:(CGContextRef)context withRect:(CGRect)rect withColor:(UIColor *)color {
  CGContextSetFillColorWithColor(context, color.CGColor);
  CGContextSetAlpha(context, 1.0);
  CGContextFillRect(context, rect);
}

- (void)fillBackgroundInContext:(CGContextRef)context withColor:(UIColor *)backgroundColor {
  CGSize imageSize = CGSizeMake(_imageWidth, _imageHeight);
  CGRect rect = CGRectZero;
  rect.size = imageSize;

  [self fillContext:context withRect:(CGRect) rect withColor:backgroundColor];
}

- (void)drawGraphWithStyle:(DSWaveformStyle)style
                    inRect:(CGRect)rect
                 onContext:(CGContextRef)context
                 withColor:(CGColorRef)graphColor {

  float graphCenter = rect.size.height / 2;
  float verticalPaddingDivisor = 1.2; // 2 = 50 % of height
  float sampleAdjustmentFactor = (rect.size.height / verticalPaddingDivisor) / 2;
  switch (style) {
    case DSWaveformStyleStripes:
      for (NSInteger intSample = 0; intSample < _sampleCount; intSample++) {
        Float32 sampleValue = (Float32) *_samples++;
        float pixels = (1.0 + sampleValue) * sampleAdjustmentFactor;
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
      for (NSInteger pointX = 0; pointX < _sampleCount; pointX++) {
        Float32 sampleValue = (Float32) *_samples++;

        float pixels = ((1.0 + sampleValue) * sampleAdjustmentFactor);
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
                   normalizeMax:(Float32)normalizeMax
                    sampleCount:(NSInteger)sampleCount
                    imageHeight:(float)imageHeight {

  CGFloat imageWidth = (CGFloat) sampleCount;
  _samples = samples;
  _normalizeMax = normalizeMax;
  CGSize imageSize = CGSizeMake(imageWidth, imageHeight);
  UIGraphicsBeginImageContext(imageSize);
  CGContextRef context = UIGraphicsGetCurrentContext();

  _sampleCount = sampleCount;
  _imageHeight = imageHeight;
  _imageWidth = imageWidth;
  [self fillBackgroundInContext:context withColor:[UIColor clearColor]];

  CGColorRef graphColor = self.graphColor.CGColor;
  CGContextSetLineWidth(context, 1.0);
  CGRect graphRect = CGRectMake(0, 0, imageWidth, imageHeight);

  [self drawGraphWithStyle:self.style inRect:graphRect onContext:context withColor:graphColor];

  // Create new image
  UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();

  // Tidy up
  UIGraphicsEndImageContext();

  return newImage;
}

- (NSData *)renderPNGAudioPictogramLogForURL:(NSURL *)url withHeight:(CGFloat)height andFramesPerPixel:(UInt32) framesPerPixel {

	
	OSStatus ret = noErr;
	
	ExtAudioFileRef extAudioFile;
	
	// Open the audio file
	CFURLRef cfURL = (__bridge CFURLRef _Nonnull)(url);
	
	ret = ExtAudioFileOpenURL(cfURL, &extAudioFile);
	
	if (ret != noErr) {
		
		assert(@"Failed to open Audio File");
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
		
		assert(@"Failed to set audio client format");
		return nil;
	}
	
	// Configure a single buffer that hold framesPerPixel frames,
	// we will use to loop through the audio file
	UInt32 bufferSize = framesPerPixel * sizeof(Float32) * asbd.mChannelsPerFrame;
	void *frames = malloc(bufferSize);
	
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
	Float32 normalizeMax = fabsf(noiseFloor);
	Float64 totalAmplitude = 0;
	
	// Read the audio and calculate data points for the wave form
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
		
		for(int j = 0; j < framesPerPixel; j++) {
			
			Float32 amplitude = ((Float32 *)frames)[j];
			amplitude = decibel(amplitude);
			amplitude = minMaxX(amplitude, noiseFloor, 0);
			
			totalAmplitude += amplitude;
		}
		
		Float32 medianAmplitude = totalAmplitude / framesPerPixel;
		if (fabsf(medianAmplitude) > fabsf(normalizeMax)) {
			normalizeMax = fabsf(medianAmplitude);
		}
		
		[waveFormData appendBytes:&medianAmplitude length:sizeof(medianAmplitude)];
		totalAmplitude = 0;
	}

    NSData *normalizedData = [self normalizeData:waveFormData normalizeMax:normalizeMax];

    UIImage *graphImage = [self audioImageLogGraph:(Float32 *) normalizedData.bytes
                                      normalizeMax:normalizeMax
                                       sampleCount:waveFormData.length / sizeof(Float32)
                                       imageHeight:_graphSize.height];

    NSData *finalData = UIImagePNGRepresentation(graphImage);

	return finalData;
}

- (NSData *)normalizeData:(NSData *)samples normalizeMax:(Float32)normalizeMax {
  NSMutableData *normalizedData = [[NSMutableData alloc] init];
  Float32 *rawData = (Float32 *) samples.bytes;

  for (int sampleIndex = 0; sampleIndex < _graphSize.width; sampleIndex++) {
    Float32 amplitude = (Float32) *rawData++;
    amplitude /= normalizeMax;
    [normalizedData appendBytes:&amplitude length:sizeof(amplitude)];
  }

  return normalizedData;
}

@end
