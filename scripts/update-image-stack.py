#!/usr/bin/env python3
import os
import sys


def slot_path(image_dir: str, index: int) -> str:
    return os.path.join(image_dir, 'latest.png' if index == 1 else f'latest-{index}.png')


def read_link(path: str):
    try:
        if os.path.islink(path):
            target = os.readlink(path)
            if os.path.isabs(target):
                return target
            return os.path.normpath(os.path.join(os.path.dirname(path), target))
    except OSError:
        return None
    return None


def replace_link(path: str, target: str):
    try:
        if os.path.lexists(path):
            os.unlink(path)
    except OSError:
        pass
    os.symlink(target, path)


def clear_path(path: str):
    try:
        if os.path.lexists(path):
            os.unlink(path)
    except OSError:
        pass


def main() -> int:
    if len(sys.argv) < 3:
        print('usage: update-image-stack.py <image-dir> <new-image-path> [stack-size]', file=sys.stderr)
        return 1

    image_dir = os.path.abspath(sys.argv[1])
    new_image = os.path.abspath(sys.argv[2])
    stack_size = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    stack_size = max(1, stack_size)

    os.makedirs(image_dir, exist_ok=True)

    ordered_targets = []
    seen = {new_image}
    for index in range(1, stack_size):
        target = read_link(slot_path(image_dir, index))
        if not target or not os.path.exists(target) or target in seen:
            continue
        ordered_targets.append(target)
        seen.add(target)

    replace_link(slot_path(image_dir, 1), new_image)

    for index in range(2, stack_size + 1):
        path = slot_path(image_dir, index)
        target_index = index - 2
        if target_index < len(ordered_targets):
            replace_link(path, ordered_targets[target_index])
        else:
            clear_path(path)

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
