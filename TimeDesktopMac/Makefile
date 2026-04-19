APP_NAME = TimeDesktop
BUNDLE = $(APP_NAME).app
EXEC = $(BUNDLE)/Contents/MacOS/$(APP_NAME)

SRCS = main.m ClockWindow.m TimezoneData.m NetTimeSync.m
HDRS = ClockWindow.h TimezoneData.h NetTimeSync.h

CC = clang
FRAMEWORKS = -framework AppKit -framework Foundation -framework Carbon
CFLAGS = -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter
LDFLAGS = $(FRAMEWORKS)

.PHONY: all clean run icon

all: $(EXEC) icon-step
	@cp Info.plist $(BUNDLE)/Contents/
	@echo "Built $(BUNDLE)"

$(EXEC): $(SRCS) $(HDRS)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)

icon-step: AppIcon.icns
	@cp AppIcon.icns $(BUNDLE)/Contents/Resources/

AppIcon.icns: gen_icon.m
	$(CC) -fobjc-arc -O2 -framework AppKit -framework Foundation -o gen_icon gen_icon.m
	./gen_icon
	@rm -f gen_icon

run: all
	@open $(BUNDLE)

clean:
	rm -rf $(BUNDLE) AppIcon.icns gen_icon AppIcon.iconset
