export function toInitials(value) {
  return value.split(" ").map(part => part[0]).join("");
}
