BUILD_DIR = build

all: $(BUILD_DIR)/heat_diffusion

$(BUILD_DIR)/heat_diffusion: $(BUILD_DIR)
	cd $(BUILD_DIR) && cmake .. && make

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

run: $(BUILD_DIR)/heat_diffusion
	mkdir -p output
	./$(BUILD_DIR)/heat_diffusion

clean:
	rm -rf $(BUILD_DIR)
	rm -rf output

.PHONY: all clean run
