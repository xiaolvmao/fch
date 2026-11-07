/*
 * 生成 App 图标：浅绿渐变底 + 白色「电话 +」符号。
 * 用法：makeicon <输出目录>
 */
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>

static BOOL WritePNG(UIImage *image, NSString *path) {
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                                 CFSTR("public.png"), 1, NULL);
    if (!dest) return NO;
    CGImageDestinationAddImage(dest, image.CGImage, NULL);
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    return ok;
}

static UIImage *RenderIcon(CGFloat size) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = YES;
    format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)
                                                                             format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        /* 浅绿渐变：上浅下稍深 */
        CGFloat comps[8] = {0.74, 0.97, 0.80, 1.0, 0.38, 0.85, 0.55, 1.0};
        CGFloat locs[2] = {0.0, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, locs, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 0), CGPointMake(0, size), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);

        UIImage *symbol = [UIImage systemImageNamed:@"phone.badge.plus"];
        if (!symbol) symbol = [UIImage systemImageNamed:@"phone.fill"];
        if (symbol) {
            UIImageSymbolConfiguration *cfg =
                [UIImageSymbolConfiguration configurationWithPointSize:size * 0.46
                                                                weight:UIImageSymbolWeightSemibold];
            symbol = [symbol imageByApplyingSymbolConfiguration:cfg];
            symbol = [symbol imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysTemplate];
            CGSize s = symbol.size;
            /* 浅底上给白色符号一点阴影，边界更清楚 */
            CGContextSetShadowWithColor(c, CGSizeMake(0, size * 0.012), size * 0.025,
                                        [UIColor colorWithWhite:0.0 alpha:0.22].CGColor);
            [symbol drawInRect:CGRectMake((size - s.width) / 2.0, (size - s.height) / 2.0, s.width, s.height)];
        } else {
            NSString *glyph = @"\u2706";
            UIFont *font = [UIFont systemFontOfSize:size * 0.5 weight:UIFontWeightSemibold];
            NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]};
            CGSize ts = [glyph sizeWithAttributes:attrs];
            [glyph drawAtPoint:CGPointMake((size - ts.width) / 2.0, (size - ts.height) / 2.0) withAttributes:attrs];
        }
    }];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { printf("用法: makeicon <输出目录>\n"); return 2; }
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

        NSArray *jobs = @[
            @[@"AppIcon60x60@2x.png", @120],
            @[@"AppIcon60x60@3x.png", @180],
            @[@"AppIcon76x76~ipad.png", @76],
            @[@"AppIcon76x76@2x~ipad.png", @152],
            @[@"AppStoreIcon.png", @1024],
        ];
        BOOL allOK = YES;
        for (NSArray *job in jobs) {
            NSString *name = job[0];
            CGFloat size = [job[1] doubleValue];
            UIImage *image = RenderIcon(size);
            NSString *path = [dir stringByAppendingPathComponent:name];
            BOOL ok = WritePNG(image, path);
            printf("%s: %s\n", name.UTF8String, ok ? "ok" : "失败");
            allOK = allOK && ok;
        }
        return allOK ? 0 : 1;
    }
}
