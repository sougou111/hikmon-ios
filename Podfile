platform :ios, '16.0'

# 只用 VLCKit 做 RTSP 拉流 + 硬解；设备侧全部走海康 ISAPI（HTTP Digest），不打包任何厂商 SDK
target 'HikMon' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.5'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
