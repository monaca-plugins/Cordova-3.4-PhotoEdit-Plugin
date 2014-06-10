//
//  PhotoEditingViewController.m
//  PhotoKitPlugin
//
//  Created by MountainLion on 09/06/14.
//  Copyright (c) 2014 Xoriant. All rights reserved.
//

#import "PhotoEditingViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

NSString *const kFilterInfoFilterNameKey = @"filterName";
NSString *const kFilterInfoDisplayNameKey = @"displayName";
NSString *const kFilterInfoPreviewImageKey = @"previewImage";

@interface PhotoEditingViewController () <PHContentEditingController,UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, weak) IBOutlet UICollectionView *collectionView;
@property (nonatomic, weak) IBOutlet UIImageView *filterPreviewView;
@property (nonatomic, weak) IBOutlet UIImageView *backgroundImageView;

@property (nonatomic, strong) NSArray *availableFilterInfos;
@property (nonatomic, strong) NSString *selectedFilterName;

@property (nonatomic, strong) UIImage *inputImage;
@property (nonatomic, strong) CIFilter *ciFilter;
@property (nonatomic, strong) CIContext *ciContext;

@property (nonatomic, strong) PHContentEditingInput *contentEditingInput;
@end

@implementation PhotoEditingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self printAllAvailableFilters];
    self.collectionView.alwaysBounceHorizontal = YES;
    self.collectionView.allowsMultipleSelection = NO;
    self.collectionView.allowsSelection = YES;
    
    NSString *plist = [[NSBundle mainBundle] pathForResource:@"Filters" ofType:@"plist"];
    self.availableFilterInfos = [NSArray arrayWithContentsOfFile:plist];
    
    self.ciContext = [CIContext contextWithOptions:nil];
    
    UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight]];
    [effectView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.view insertSubview:effectView aboveSubview:self.backgroundImageView];
    
    NSArray *verticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[effectView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(effectView)];
    NSArray *horizontalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[effectView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(effectView)];
    [self.view addConstraints:verticalConstraints];
    [self.view addConstraints:horizontalConstraints];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    NSInteger item = [self.availableFilterInfos indexOfObjectPassingTest:^BOOL(NSDictionary *filterInfo, NSUInteger idx, BOOL *stop) {
        return [filterInfo[kFilterInfoFilterNameKey] isEqualToString:self.selectedFilterName];
    }];
    if (item != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:0];
        [self.collectionView selectItemAtIndexPath:indexPath animated:NO
                                    scrollPosition:UICollectionViewScrollPositionCenteredHorizontally];
        [self updateSelectionForCell:[self.collectionView cellForItemAtIndexPath:indexPath]];
    }
}



-(void)printAllAvailableFilters {
    NSArray *filterProperties = [CIFilter filterNamesInCategory: kCICategoryBuiltIn];
    NSLog(@"filterProperties: %@", filterProperties);
    for (NSString *filterName in filterProperties) {
        CIFilter *filter = [CIFilter filterWithName:filterName];
        NSLog(@"filter: %@", [filter attributes]);
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - PHContentEditingController

- (BOOL)canHandleAdjustmentData:(PHAdjustmentData *)adjustmentData {
    BOOL result = [adjustmentData.formatIdentifier isEqualToString:@"com.apple.photo-editing"];
    result &= [adjustmentData.formatVersion isEqualToString:@"1.0"];
    return result;
}

- (void)startContentEditingWithInput:(PHContentEditingInput *)contentEditingInput placeholderImage:(UIImage *)placeholderImage {
    self.contentEditingInput = contentEditingInput;
   
    self.inputImage = self.contentEditingInput.displaySizeImage;
    
    @try {
        PHAdjustmentData *adjustmentData = self.contentEditingInput.adjustmentData;
        if (adjustmentData) {
            self.selectedFilterName = [NSKeyedUnarchiver unarchiveObjectWithData:adjustmentData.data];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception decoding adjustment data: %@", exception);
    }
    if (!self.selectedFilterName) {
        NSString *defaultFilterName = @"CISepiaTone";
        self.selectedFilterName = defaultFilterName;
    }
    
    [self updateFilter];
    [self updateFilterPreview];
    self.backgroundImageView.image = placeholderImage;
}

- (void)finishContentEditingWithCompletionHandler:(void (^)(PHContentEditingOutput *))completionHandler {
    PHContentEditingOutput *contentEditingOutput = [[PHContentEditingOutput alloc] initWithContentEditingInput:self.contentEditingInput];
    
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:self.selectedFilterName];
    PHAdjustmentData *adjustmentData = [[PHAdjustmentData alloc] initWithFormatIdentifier:@"com.apple.photo-editing"
                                                                            formatVersion:@"1.0"
                                                                                     data:archivedData];
    contentEditingOutput.adjustmentData = adjustmentData;
    
            NSURL *url = self.contentEditingInput.fullSizeImageURL;
        NSLog(@"url image:%@",url);
            int orientation = self.contentEditingInput.fullSizeImageOrientation;
            
            UIImage *image = [UIImage imageWithContentsOfFile:url.path];
            image = [self transformedImage:image withOrientation:orientation usingFilter:self.ciFilter];
            NSData *renderedJPEGData = UIImageJPEGRepresentation(image, 0.9f);
            
            NSError *error = nil;
            BOOL success = [renderedJPEGData writeToURL:contentEditingOutput.renderedContentURL options:NSDataWritingAtomic error:&error];
            if (success) {
                completionHandler(contentEditingOutput);
            } else {
                NSLog(@"An error occured: %@", error);
                completionHandler(nil);
        }
    
}

- (void)cancelContentEditing {
    // Handle cancellation
}

#pragma mark - Image Filtering

- (void)updateFilter {
    self.ciFilter = [CIFilter filterWithName:self.selectedFilterName];
    
    CIImage *inputImage = [CIImage imageWithCGImage:self.inputImage.CGImage];
    int orientation = [self orientationFromImageOrientation:self.inputImage.imageOrientation];
    inputImage = [inputImage imageByApplyingOrientation:orientation];
    
    [self.ciFilter setValue:inputImage forKey:kCIInputImageKey];
}

- (void)updateFilterPreview {
    CIImage *outputImage = self.ciFilter.outputImage;
    
    CGImageRef cgImage = [self.ciContext createCGImage:outputImage fromRect:outputImage.extent];
    UIImage *transformedImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    
    self.filterPreviewView.image = transformedImage;
}

- (UIImage *)transformedImage:(UIImage *)image withOrientation:(int)orientation usingFilter:(CIFilter *)filter {
    CIImage *inputImage = [CIImage imageWithCGImage:image.CGImage];
    inputImage = [inputImage imageByApplyingOrientation:orientation];
    
    [self.ciFilter setValue:inputImage forKey:kCIInputImageKey];
    CIImage *outputImage = [self.ciFilter outputImage];
    
    CGImageRef cgImage = [self.ciContext createCGImage:outputImage fromRect:outputImage.extent];
    UIImage *transformedImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    
    return transformedImage;
}




#pragma mark - UICollectionViewDataSource & UICollectionViewDelegate

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.availableFilterInfos.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *filterInfo = self.availableFilterInfos[indexPath.item];
    NSString *displayName = filterInfo[kFilterInfoDisplayNameKey];
    NSString *previewImageName = filterInfo[kFilterInfoPreviewImageKey];
    
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"PhotoFilterCell" forIndexPath:indexPath];
    
    UIImageView *imageView = (UIImageView *)[cell viewWithTag:999];
    imageView.image = [UIImage imageNamed:previewImageName];
    
    UILabel *label = (UILabel *)[cell viewWithTag:998];
    label.text = displayName;
    
    [self updateSelectionForCell:cell];
    
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedFilterName = self.availableFilterInfos[indexPath.item][kFilterInfoFilterNameKey];
    [self updateFilter];
    
    [self updateSelectionForCell:[collectionView cellForItemAtIndexPath:indexPath]];
    
    [self updateFilterPreview];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self updateSelectionForCell:[collectionView cellForItemAtIndexPath:indexPath]];
}

- (void)updateSelectionForCell:(UICollectionViewCell *)cell {
    BOOL isSelected = cell.selected;
    
    UIImageView *imageView = (UIImageView *)[cell viewWithTag:999];
    imageView.layer.borderColor = self.view.tintColor.CGColor;
    imageView.layer.borderWidth = isSelected ? 2.0 : 0.0;
    
    UILabel *label = (UILabel *)[cell viewWithTag:998];
    label.textColor = isSelected ? self.view.tintColor : [UIColor whiteColor];
}

#pragma mark - Utilities

// Returns the EXIF/TIFF orientation value corresponding to the given UIImageOrientation value.
- (int)orientationFromImageOrientation:(UIImageOrientation)imageOrientation {
    int orientation = 0;
    switch (imageOrientation) {
        case UIImageOrientationUp:            orientation = 1; break;
        case UIImageOrientationDown:          orientation = 3; break;
        case UIImageOrientationLeft:          orientation = 8; break;
        case UIImageOrientationRight:         orientation = 6; break;
        case UIImageOrientationUpMirrored:    orientation = 2; break;
        case UIImageOrientationDownMirrored:  orientation = 4; break;
        case UIImageOrientationLeftMirrored:  orientation = 5; break;
        case UIImageOrientationRightMirrored: orientation = 7; break;
        default: break;
    }
    return orientation;
}





@end
